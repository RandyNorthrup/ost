import QtQuick
import QtQuick.Controls.Basic

// The open chat: header with tabs and actions, message list, compose box.
Rectangle {
    id: root
    property string chatName
    property var messages: []
    property bool busy
    signal send(string text)
    signal call()
    property string chatPresence: ""
    property string typingText: ""
    /// Channel conversations (posts) look different from chats in Teams.
    property bool isChannel: false
    property string teamName: ""
    /// The other person's id in a 1:1 chat, for the header picture.
    property string chatPhotoId: ""
    /// The open chat's id; unsent text is kept per chat as a draft.
    property string chatId: ""
    property string draftChat: ""
    // Test hooks for the compose box.
    function setComposeText(t) { input.text = t }
    function composeText() { return input.text }
    onChatIdChanged: {
        if (draftChat && !editingId) backend.setDraft(draftChat, input.text)
        editingId = ""
        input.text = chatId ? backend.draftFor(chatId) : ""
        draftChat = chatId
    }
    // Keep the draft current while typing (so it survives a quit).
    Timer {
        id: draftSave
        interval: 1000
        onTriggered: if (root.draftChat && !root.editingId) backend.setDraft(root.draftChat, input.text)
    }
    /// Your own notes chat: Teams drops the call and people buttons and
    /// shows only the Chat, Shared and Storyline tabs.
    property bool isSelf: false
    signal typing()
    signal react(string messageId, string key, bool on)
    signal editMessage(string messageId, string text)
    signal deleteMessage(string messageId)
    // Set while the compose box edits an existing message.
    property string editingId: ""

    // Newest first (the list grows upward), with Teams' grouping: a message
    // joins the previous one when the same person sent it under 5 minutes
    // later. latestMine marks your newest message for the sent tick.
    // Teams' relative dates: the time alone today, then "Yesterday 3:05 PM",
    // the weekday within a week, and the date beyond that.
    function daysAgo(d) {
        const a = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const now = new Date()
        const b = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        return Math.round((b - a) / 86400000)
    }
    function stamp(t) {
        const d = new Date(t), n = daysAgo(d), time = Qt.formatTime(d, "h:mm AP")
        if (n === 0) return time
        if (n === 1) return "Yesterday " + time
        if (n > 1 && n < 7) return Qt.formatDate(d, "dddd") + " " + time
        if (d.getFullYear() === new Date().getFullYear()) return Qt.formatDate(d, "M/d") + " " + time
        return Qt.formatDate(d, "M/d/yyyy") + " " + time
    }
    function dayLabel(t) {
        const d = new Date(t), n = daysAgo(d)
        if (n === 0) return "Today"
        if (n === 1) return "Yesterday"
        if (n > 1 && n < 7) return Qt.formatDate(d, "dddd")
        if (d.getFullYear() === new Date().getFullYear()) return Qt.formatDate(d, "MMMM d")
        return Qt.formatDate(d, "MMMM d, yyyy")
    }

    function annotate(msgs) {
        const out = msgs.map(m => Object.assign({}, m))
        for (let i = 0; i < out.length; i++) {
            const prev = i > 0 ? out[i - 1] : null, cur = out[i]
            // A day divider where the day changes (not above the very first
            // message shown), and the "Last read" line where unread begins.
            const day = new Date(cur.time).toDateString()
            cur.dayDivider = prev && new Date(prev.time).toDateString() !== day ? root.dayLabel(cur.time) : ""
            cur.lastRead = cur.first_unread === true && i > 0
            if (!prev) continue
            const gap = new Date(cur.time) - new Date(prev.time)
            // Channel posts each get their own card and header; a divider
            // also starts a new group.
            cur.grouped = !root.isChannel && cur.kind !== "call" && prev.kind !== "call"
                && !cur.dayDivider && !cur.lastRead
                && cur.sender === prev.sender && cur.mine === prev.mine && gap >= 0 && gap < 5 * 60 * 1000
        }
        // Whether the next message continues this one's group (Teams squares
        // the corners where grouped bubbles meet).
        for (let i = 0; i < out.length; i++) out[i].groupNext = i + 1 < out.length && out[i + 1].grouped === true
        // Teams' receipts: your newest message carries the sent tick until
        // it is read; the newest one the other person has read gets the eye.
        for (let i = out.length - 1; i >= 0; i--) {
            if (out[i].mine && out[i].kind !== "call") { out[i].latestMine = true; break }
        }
        for (let i = out.length - 1; i >= 0; i--) {
            if (out[i].mine && out[i].kind !== "call" && out[i].seen) { out[i].latestSeen = true; break }
        }
        return out.reverse()
    }
    color: theme.surface

    // Header
    Item {
        id: header
        width: parent.width; height: theme.headerHeight
        visible: root.chatName.length > 0
        Avatar {
            visible: !root.isChannel
            x: 20; anchors.verticalCenter: parent.verticalCenter; size: 32
            name: root.chatName; presence: root.chatPresence
            photoId: root.chatPhotoId
        }
        Rectangle {
            visible: root.isChannel
            x: 20; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32; radius: theme.radius
            readonly property var colors: ["#C43E1C", "#0F6CBD", "#107C10", "#8764B8", "#038387", "#CA5010"]
            color: {
                let h = 0
                for (let i = 0; i < root.teamName.length; i++) h = (h * 31 + root.teamName.charCodeAt(i)) % 997
                return colors[h % colors.length]
            }
            Text {
                anchors.centerIn: parent
                text: root.teamName.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                color: "white"
                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            }
        }
        // Title, tabs and actions at Teams desktop's measured positions.
        Text {
            id: title
            x: 61; anchors.verticalCenter: parent.verticalCenter
            // Long names elide so the tabs and actions keep their place.
            width: Math.min(implicitWidth, parent.width * 0.35)
            elide: Text.ElideRight
            text: root.chatName
            font.family: theme.font; font.pixelSize: theme.title; font.weight: Font.Bold
            color: theme.text
        }
        Row {
            id: tabs
            x: title.x + title.width + 2
            y: 2; height: 56
            Repeater {
                model: root.isChannel ? ["Posts", "Files"]
                    : root.isSelf ? ["Chat", "Shared", "Storyline"]
                    : ["Chat", "Shared", "Notes", "Recap", "Storyline"]
                delegate: Item {
                    required property string modelData
                    required property int index
                    // 6 px padding each side of the label.
                    width: tabText.implicitWidth + 12; height: parent.height
                    Text {
                        id: tabText
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        font.family: theme.font; font.pixelSize: theme.base
                        font.weight: index === 0 ? Font.DemiBold : Font.Normal
                        color: index === 0 ? theme.text : theme.textStrong
                    }
                    // Selected: a 3 px brand pill, inset 8 px, at the bottom.
                    Rectangle {
                        visible: index === 0
                        x: 8; width: tabText.implicitWidth - 4; height: 3; radius: 1.5
                        anchors.bottom: parent.bottom
                        color: theme.brand
                    }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData
                }
            }
            Item {
                width: 32; height: parent.height
                FluentIcon { anchors.centerIn: parent; name: "add-square-20"; size: 20; color: theme.textStrong }
                Accessible.role: Accessible.Button
                Accessible.name: "Add a tab"
            }
        }
        component HeaderAction: Rectangle {
            id: ha
            property alias icon: haIcon.name
            property int iconSize: 20
            signal clicked()
            width: 32; height: 32; radius: theme.radius
            anchors.verticalCenter: parent.verticalCenter
            color: haHover.hovered ? theme.hover : "transparent"
            HoverHandler { id: haHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ha.clicked() }
            FluentIcon { id: haIcon; anchors.centerIn: parent; size: ha.iconSize; color: theme.textStrong }
        }
        HeaderAction {
            visible: !root.isSelf && !root.isChannel
            x: parent.width - 199; width: 24
            icon: "call-20"
            onClicked: root.call()
            Accessible.name: "Audio call"
        }
        HeaderAction {
            visible: !root.isSelf && !root.isChannel
            x: parent.width - 175; width: 24
            icon: "chevron-down-16"; iconSize: 16
            Accessible.name: "More call options"
        }
        HeaderAction {
            visible: !root.isSelf
            x: parent.width - 151; width: 28
            icon: "people-add-20"
            Accessible.name: "View and add participants"
        }
        Rectangle {
            visible: !root.isSelf
            x: parent.width - 116; width: 1; height: 20
            anchors.verticalCenter: parent.verticalCenter
            color: theme.divider
        }
        HeaderAction { x: parent.width - 107; icon: "search-20"; Accessible.name: "Find in chat" }
        HeaderAction { x: parent.width - 75; icon: "panel-left-20"; Accessible.name: "Open chat details" }
        HeaderAction { x: parent.width - 43; icon: "more-20"; Accessible.name: "More chat options" }
        Rectangle { width: parent.width; height: 1; anchors.bottom: parent.bottom; color: theme.dividerSoft }
    }

    Text {
        anchors.centerIn: parent
        visible: root.chatName.length === 0
        text: "Select a chat to start messaging"
        font.family: theme.font; font.pixelSize: theme.base
        color: theme.textSecondary
    }

    ListView {
        id: list
        anchors { top: header.bottom; bottom: compose.top; left: parent.left; right: parent.right }
        anchors.bottomMargin: 12
        clip: true
        spacing: 0
        verticalLayoutDirection: ListView.BottomToTop
        model: root.annotate(root.messages)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Item {
            id: msg
            required property var modelData
            // In channels every post is a left-aligned card, yours included.
            readonly property bool mine: modelData.mine && !root.isChannel
            readonly property bool isCall: modelData.kind === "call"
            readonly property var reactions: modelData.reactions || []
            width: list.width
            // Grouped messages (same sender, within minutes) drop the
            // name/time line and avatar, and sit 2 px under the previous.
            readonly property bool grouped: modelData.grouped === true
            // Day divider and "Last read" line sit above the message.
            readonly property int dividerH: (modelData.dayDivider ? 30 : 0) + (modelData.lastRead ? 36 : 0)
            readonly property int topPad: dividerH + (grouped ? 2 : 12)
            readonly property int bubbleY: topPad + (grouped || isCall ? 0 : meta.height + 2)
            height: isCall ? topPad + callRow.height
                : bubbleY + bubble.height + (reactions.length > 0 ? reactionRow.height + 4 : 0)
            readonly property int maxBubble: root.isChannel ? Math.min(900, list.width - 144) : Math.min(640, list.width * 0.7)

            // Measured from Teams: the label's centre 22 px below the
            // previous message, 28 px above the next header's.
            Text {
                visible: !!msg.modelData.dayDivider
                y: 22 - height / 2
                anchors.horizontalCenter: parent.horizontalCenter
                text: msg.modelData.dayDivider || ""
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textSecondary
                Accessible.role: Accessible.Separator
            }
            Item {
                visible: msg.modelData.lastRead === true
                y: msg.modelData.dayDivider ? 30 : 0
                x: 72; width: parent.width - 144; height: 36
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 0; width: lastReadText.x - 24; height: 1; color: theme.brand
                }
                Text {
                    id: lastReadText
                    anchors.centerIn: parent
                    text: "Last read"
                    font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.DemiBold
                    color: theme.brand
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: lastReadText.x + lastReadText.width + 24
                    width: parent.width - x; height: 1; color: theme.brand
                }
                Accessible.role: Accessible.Separator
                Accessible.name: "Last read"
            }

            // Call events: an icon, the time and "Call ended 3m 9s" / "Call missed".
            Row {
                id: callRow
                visible: msg.isCall
                x: 72; y: msg.topPad
                height: 24; spacing: 12
                FluentIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: msg.modelData.call_state === "missed" ? "call-missed-16" : "call-20"
                    size: 16
                    color: msg.modelData.call_state === "missed" ? theme.danger : theme.icon
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.stamp(msg.modelData.time)
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.textSecondary
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (msg.modelData.call_state === "missed") return "Call missed"
                        const s = msg.modelData.call_seconds, m = Math.floor(s / 60)
                        return "Call ended  " + (m > 0 ? m + "m " : "") + (s % 60) + "s"
                    }
                    font.family: theme.font; font.pixelSize: theme.small
                    color: theme.text
                }
            }

            Avatar {
                visible: !msg.mine && !msg.grouped && !msg.isCall
                x: 32; y: msg.bubbleY
                size: 32; name: msg.modelData.sender
                photoId: msg.modelData.sender_mri || ""
                // Teams shows the sender's presence on message avatars too.
                presence: msg.modelData.sender_mri && msg.modelData.sender_mri === root.chatPhotoId ? root.chatPresence : ""
            }
            Text {
                id: meta
                visible: !msg.grouped && !msg.isCall
                y: msg.topPad
                text: (msg.mine ? "" : msg.modelData.sender + "  ") + root.stamp(msg.modelData.time)
                    + (msg.modelData.edited ? "   Edited" : "")
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textSecondary
                x: msg.mine ? parent.width - 72 - implicitWidth : 72
            }
            Rectangle {
                id: bubble
                visible: !msg.isCall
                y: msg.bubbleY
                readonly property var imgs: msg.modelData.images || []
                readonly property bool imageOnly: imgs.length > 0 && msg.modelData.text === "Image"
                // A picture on its own is shown bare, without the bubble.
                readonly property bool bare: imageOnly && !root.isChannel
                readonly property real pad: bare ? 0 : 15.7
                width: root.isChannel ? msg.maxBubble
                    : Math.min(msg.maxBubble, Math.max(imageOnly ? 0 : body.implicitWidth, pics.implicitWidth) + 2 * pad)
                height: (imageOnly ? 0 : body.implicitHeight) + (imgs.length > 0 ? pics.implicitHeight + (imageOnly ? 0 : 8) : 0) + (bare ? 0 : 15.3)
                // Teams: 6 px corners, squared on the inner side where a
                // group's bubbles meet (bottom of the first, top of the rest).
                readonly property real r: root.isChannel ? theme.radius : 6
                readonly property bool joinUp: !root.isChannel && msg.grouped
                readonly property bool joinDown: !root.isChannel && msg.modelData.groupNext === true
                radius: r
                topLeftRadius: !msg.mine && joinUp ? 0 : r
                bottomLeftRadius: !msg.mine && joinDown ? 0 : r
                topRightRadius: msg.mine && joinUp ? 0 : r
                bottomRightRadius: msg.mine && joinDown ? 0 : r
                color: bare ? "transparent" : root.isChannel ? theme.surface : (msg.mine ? theme.brandTint : theme.bubble)
                border.color: root.isChannel ? theme.dividerSoft : "transparent"
                x: msg.mine ? parent.width - 72 - width : 72
                // Inline pictures, scaled to fit the bubble (as in Teams).
                Column {
                    id: pics
                    x: bubble.pad; y: bubble.bare ? 0 : bubble.imageOnly ? 8 : body.y + body.implicitHeight + 8
                    spacing: 4
                    Repeater {
                        model: bubble.imgs
                        // Rounded 4 px with a hairline border, as Teams draws them.
                        Item {
                            required property var modelData
                            readonly property real maxW: msg.maxBubble - 2 * bubble.pad
                            readonly property real w0: modelData.width > 0 ? modelData.width : 240
                            readonly property real h0: modelData.height > 0 ? modelData.height : 160
                            width: Math.min(maxW, w0); height: width * h0 / w0
                            Image {
                                anchors.fill: parent
                                source: parent.modelData.local_path || ""
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            RoundedCorners {
                                anchors.fill: parent
                                radius: theme.radius
                                background: bubble.bare ? root.color : bubble.color
                            }
                            Rectangle { anchors.fill: parent; color: "transparent"; border.color: theme.dividerSoft; radius: theme.radius }
                            Accessible.role: Accessible.Graphic
                            Accessible.name: "Image"
                        }
                    }
                }
                Text {
                    id: body
                    visible: !bubble.imageOnly
                    x: bubble.pad; y: 6.7
                    width: Math.min(msg.maxBubble - 2 * bubble.pad, implicitWidth)
                    // Teams' 14/20 text.
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    // Sanitised by the engine to a safe subset.
                    text: msg.modelData.deleted ? "This message has been deleted."
                        : "<style>a { color: " + theme.brand + "; text-decoration: none; }</style>"
                          + (msg.modelData.html || msg.modelData.text)
                    textFormat: msg.modelData.deleted ? Text.PlainText : Text.RichText
                    wrapMode: Text.Wrap
                    font.family: theme.font; font.pixelSize: theme.base
                    font.italic: msg.modelData.deleted === true
                    color: msg.modelData.deleted ? theme.textSecondary : theme.text
                    linkColor: theme.brand
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    HoverHandler { cursorShape: body.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
                    Accessible.name: msg.modelData.text
                }
            }
            // Reaction pills under the bubble, as in Teams; yours has a brand
            // outline. Clicking one toggles your reaction.
            Row {
                id: reactionRow
                visible: msg.reactions.length > 0
                y: bubble.y + bubble.height + 4
                x: msg.mine ? parent.width - 72 - width : 72 + 8
                spacing: 4
                Repeater {
                    model: msg.reactions
                    Rectangle {
                        required property var modelData
                        width: pill.implicitWidth + 16; height: 24; radius: 12
                        color: modelData.mine ? theme.brandTint : theme.surface
                        border.color: modelData.mine ? theme.brand : theme.stroke
                        Row {
                            id: pill
                            anchors.centerIn: parent; spacing: 4
                            Text { text: parent.parent.modelData.emoji; font.pixelSize: 14 }
                            Text {
                                visible: parent.parent.modelData.count > 1
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.modelData.count
                                font.family: theme.font; font.pixelSize: theme.small
                                color: theme.text
                            }
                        }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.react(msg.modelData.id, modelData.key, !modelData.mine) }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.count + " " + modelData.key + " reaction" + (modelData.mine ? ", including yours" : "")
                    }
                }
            }
            HoverHandler { id: msgHover }
            // Hover bar: quick reactions and More, at the bubble's top edge.
            Rectangle {
                id: actions
                readonly property bool can: !msg.isCall && !msg.modelData.deleted
                visible: can && (msgHover.hovered || barHover.hovered || menu.visible)
                z: 5
                height: 32; width: actionRow.implicitWidth + 8; radius: theme.radius
                color: theme.surface
                border.color: theme.dividerSoft
                y: bubble.y - 22
                x: msg.mine ? bubble.x : Math.max(72, bubble.x + bubble.width - width)
                HoverHandler { id: barHover }
                Row {
                    id: actionRow
                    x: 4; anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: [["like", "👍"], ["heart", "❤️"], ["laugh", "😆"], ["surprised", "😮"], ["sad", "😢"]]
                        Rectangle {
                            required property var modelData
                            readonly property bool mineAlready: msg.reactions.some(r => r.key === modelData[0] && r.mine)
                            width: 30; height: 28; radius: theme.radius
                            color: emojiHover.hovered ? theme.pane : "transparent"
                            Text { anchors.centerIn: parent; text: parent.modelData[1]; font.pixelSize: 16 }
                            HoverHandler { id: emojiHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.react(msg.modelData.id, parent.modelData[0], !parent.mineAlready) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "React with " + modelData[0]
                        }
                    }
                    Rectangle { width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: theme.dividerSoft }
                    Rectangle {
                        visible: msg.mine
                        width: 30; height: 28; radius: theme.radius
                        color: moreHover.hovered ? theme.pane : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "more-20"; size: 16 }
                        HoverHandler { id: moreHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: menu.open() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "More options"
                    }
                }
                Menu {
                    id: menu
                    y: actions.height
                    MenuItem {
                        text: "Edit"
                        onTriggered: { root.editingId = msg.modelData.id; input.text = msg.modelData.text; input.forceActiveFocus() }
                    }
                    MenuItem {
                        text: "Delete"
                        onTriggered: root.deleteMessage(msg.modelData.id)
                    }
                }
            }
            // Sent tick on your newest message, "Seen" eye on the newest one
            // the other person has read.
            FluentIcon {
                readonly property bool seen: msg.modelData.latestSeen === true
                visible: msg.mine && !msg.isCall && (seen || (msg.modelData.latestMine === true && !msg.modelData.seen))
                name: seen ? "seen-12" : "sent-12"; size: 12; color: theme.brand
                x: bubble.x + bubble.width + 8
                y: bubble.y + bubble.height - 14
                Accessible.name: seen ? "Seen" : "Sent"
            }
        }
    }

    // Typing indicator, as Teams draws it: the typist's avatar overlapping
    // the compose box's top-left edge with three pulsing dots (the text is
    // the accessible name).
    Item {
        id: typingRow
        visible: root.typingText.length > 0
        z: 2
        x: compose.x + 16; y: compose.y - 24
        width: 32 + 6 + 3 * 6 + 2 * 3; height: 32
        Accessible.role: Accessible.StaticText
        Accessible.name: root.typingText
        Avatar { size: 32; name: root.typingText.replace(/ is typing$/, "") }
        Row {
            x: 38; anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: 6; height: 6; radius: 3
                    color: "#C8C6C4"
                    SequentialAnimation on color {
                        running: typingRow.visible
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 200 }
                        ColorAnimation { to: theme.brand; duration: 200 }
                        ColorAnimation { to: "#C8C6C4"; duration: 200 }
                        PauseAnimation { duration: (2 - index) * 200 + 200 }
                    }
                }
            }
        }
    }

    // "Editing" strip above the compose box while editing a message.
    Rectangle {
        visible: root.editingId.length > 0
        anchors { left: compose.left; right: compose.right; bottom: compose.top; bottomMargin: 2 }
        height: 28; radius: theme.radius
        color: theme.brandTint
        Text {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            text: "Editing message — Enter to save, Esc to cancel"
            font.family: theme.font; font.pixelSize: theme.small
            color: theme.text
        }
    }

    // Compose box
    Rectangle {
        id: compose
        visible: root.chatName.length > 0
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.leftMargin: 72; anchors.rightMargin: 72; anchors.bottomMargin: 24
        height: Math.max(44, input.contentHeight + 24)
        radius: theme.radius
        color: theme.input
        border.color: input.activeFocus ? theme.brand : theme.divider
        TextArea {
            id: input
            anchors { left: parent.left; right: tools.left; verticalCenter: parent.verticalCenter }
            anchors.leftMargin: 4
            placeholderText: root.isChannel ? "Start a post" : "Type a message"
            placeholderTextColor: theme.textSecondary
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            wrapMode: TextArea.Wrap
            background: null
            onActiveFocusChanged: if (activeFocus) enterKey = backend.setting("enterKey") || "send"
            onTextChanged: {
                if (text.length > 0) root.typing()
                draftSave.restart()
            }
            // Settings > Chats and channels: Enter sends (Shift+Enter breaks the
            // line), or Enter breaks the line and Ctrl+Enter sends.
            property string enterKey: backend.setting("enterKey") || "send"
            Keys.onReturnPressed: event => {
                const sendKey = enterKey === "newline" ? (event.modifiers & Qt.ControlModifier) : !(event.modifiers & Qt.ShiftModifier)
                if (!sendKey) { event.accepted = false; return }
                if (root.editingId) { root.editMessage(root.editingId, input.text); root.editingId = "" }
                else root.send(input.text)
                input.text = ""
            }
            Keys.onEscapePressed: if (root.editingId) { root.editingId = ""; input.text = "" }
        }
        Row {
            id: tools
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            FluentIcon { name: "format-20" }
            FluentIcon { name: "emoji-20" }
            FluentIcon { name: "attach-20" }
            FluentIcon { name: "add-20" }
            Rectangle { width: 1; height: 20; color: theme.divider }
            FluentIcon {
                name: input.text.length > 0 ? "send-20-filled" : "send-20"
                color: input.text.length > 0 ? theme.brand : theme.icon
                TapHandler { onTapped: { root.send(input.text); input.text = "" } }
            }
        }
    }
}
