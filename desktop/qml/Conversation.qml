import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs

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
    /// The channel's team (its picture is the header's).
    property string teamId: ""
    /// The other person's id in a 1:1 chat, for the header picture.
    property string chatPhotoId: ""
    /// A group chat (a grey people picture, as in Teams).
    property bool isGroup: false
    /// Your name, for the participants list.
    property string myName: ""
    /// The open chat's id; unsent text is kept per chat as a draft.
    property string chatId: ""
    property string draftChat: ""
    /// Shown as a side pane (in the call window): a plain "Chat" header
    /// with a close button instead of the title, tabs and actions.
    property bool pane: false
    signal closePane()
    /// In a channel: reply to a post, and whether a new post is being written.
    signal sendReply(string rootId, string text)
    property bool posting: false
    // Keyboard shortcuts (Ctrl+R, Ctrl+F, Ctrl+J, Alt+P, Alt+1-9, Alt+Shift+O).
    function focusCompose() { if (compose.visible) input.forceActiveFocus() }
    function openFind() { finding = true; tab = ""; findField.forceActiveFocus() }
    function jumpToNewest() { tab = ""; list.positionViewAtBeginning(); channelPosts.toEnd() }
    function toggleDetails() { participants.visible = !participants.visible }
    readonly property var tabNames: isChannel ? ["Posts", "Shared", "Notes"]
        : isSelf ? ["Chat", "Shared", "Storyline"] : ["Chat", "Shared", "Notes", "Recap", "Storyline"]
    function openTab(i) { if (i < tabNames.length) tab = i === 0 ? "" : tabNames[i] }
    readonly property bool composeFocused: input.activeFocus
    readonly property bool detailsOpen: participants.visible
    function attachFile() { if (compose.visible) filePicker.open() }
    function replyForTest(text) { return channelPosts.replyToNewestForTest(text) }
    // Test hooks for the compose box.
    function setComposeText(t) { root.setPlain(t) }
    function composeText() { return root.plainText() }
    // The compose box is rich text (Teams formats as you type); these read
    // and write it as plain text.
    function escapeHtml(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>") }
    function plainText() { return input.getText(0, input.length) }
    function setPlain(t) { input.clear(); if (t) input.insert(0, root.escapeHtml(t)) }
    function attachForTest(paths) { root.pendingFiles = paths }
    function openEmojiForTest() { emojiPicker.open() }
    function formatForTest(a, b, tag) { input.select(a, b); root.wrapSelection(tag) }
    function openParticipantsForTest() { participants.visible = true }
    function findForTest(q) { root.finding = true; findField.text = q; return root.findHits.length }
    function sendForTest() { root.sendCompose() }
    onChatIdChanged: {
        tab = ""; finding = false; findField.text = ""; participants.visible = false; posting = false
        if (draftChat && !editingId) backend.setDraft(draftChat, root.plainText())
        editingId = ""
        root.setPlain(chatId ? backend.draftFor(chatId) : "")
        draftChat = chatId
    }
    // Keep the draft current while typing (so it survives a quit).
    Timer {
        id: draftSave
        interval: 1000
        onTriggered: if (root.draftChat && !root.editingId) backend.setDraft(root.draftChat, root.plainText())
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
        Text {
            visible: root.pane
            x: 16; anchors.verticalCenter: parent.verticalCenter
            text: "Chat"
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
        }
        HeaderAction {
            visible: root.pane
            x: parent.width - 44; icon: "dismiss-20"; Accessible.name: "Close chat"
            onClicked: root.closePane()
        }
        Item {
        visible: !root.pane
        anchors.fill: parent
        Avatar {
            visible: !root.isChannel
            x: 20; anchors.verticalCenter: parent.verticalCenter; size: 32
            name: root.chatName; presence: root.chatPresence
            photoId: root.chatPhotoId
            group: root.isGroup && !root.chatPhotoId
        }
        Avatar {
            visible: root.isChannel
            x: 20; anchors.verticalCenter: parent.verticalCenter
            size: 32; square: true
            name: root.teamName
            initialsText: root.teamName.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
            photoId: root.teamId ? "team:" + root.teamId : ""
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
                model: root.tabNames
                delegate: Item {
                    id: tabItem
                    required property string modelData
                    required property int index
                    readonly property bool sel: root.tab === modelData || (index === 0 && root.tab === "")
                    // 6 px padding each side of the label.
                    width: tabText.implicitWidth + 12; height: parent.height
                    // Tabs that would run under the header actions are hidden
                    // (opacity, so the row's layout doesn't depend on it).
                    readonly property bool fits: tabs.x + x + width <= header.width
                        - (root.pane ? 48 : root.isSelf ? 115 : root.isChannel ? 160 : 207)
                    opacity: fits ? 1 : 0
                    enabled: fits
                    Text {
                        id: tabText
                        x: 6; anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        font.family: theme.font; font.pixelSize: theme.base
                        font.weight: tabItem.sel ? Font.DemiBold : Font.Normal
                        color: tabItem.sel ? theme.text : theme.textStrong
                    }
                    // Selected: a 3 px brand pill, inset 8 px, at the bottom.
                    Rectangle {
                        visible: tabItem.sel
                        x: 8; width: tabText.implicitWidth - 4; height: 3; radius: 1.5
                        anchors.bottom: parent.bottom
                        color: theme.brand
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.tab = tabItem.index === 0 ? "" : tabItem.modelData }
                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData
                    Accessible.selected: sel
                }
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
            onClicked: callMenu.open()
            MenuPopup {
                id: callMenu
                x: -200; y: parent.height + 4
                items: [{ label: "Audio call", icon: "call-20" }]
                onPicked: root.call()
            }
        }
        HeaderAction {
            visible: !root.isSelf
            x: parent.width - 151; width: 28
            icon: "people-add-20"
            Accessible.name: "View participants"
            onClicked: participants.visible = !participants.visible
        }
        Rectangle {
            visible: !root.isSelf
            x: parent.width - 116; width: 1; height: 20
            anchors.verticalCenter: parent.verticalCenter
            color: theme.divider
        }
        HeaderAction {
            x: parent.width - 107; icon: "search-20"; Accessible.name: "Find in chat"
            onClicked: { root.finding = !root.finding; if (root.finding) { root.tab = ""; findField.forceActiveFocus() } else findField.text = "" }
        }
        HeaderAction {
            x: parent.width - 75; icon: "panel-left-20"; Accessible.name: "Open chat details"
            onClicked: participants.visible = !participants.visible
        }
        }
        Rectangle { width: parent.width; height: 1; anchors.bottom: parent.bottom; color: theme.dividerSoft }
    }

    Text {
        anchors.centerIn: parent
        visible: root.chatName.length === 0
        text: "Select a chat to start messaging"
        font.family: theme.font; font.pixelSize: theme.base
        color: theme.textSecondary
    }

    ChannelPosts {
        id: channelPosts
        visible: root.isChannel && root.tab === ""
        anchors { top: findBar.visible ? findBar.bottom : header.bottom; bottom: root.posting ? compose.top : parent.bottom; left: parent.left; right: parent.right }
        anchors.bottomMargin: root.posting ? 12 : 0
        messages: root.isChannel ? root.messages : []
        myName: root.myName
        busy: root.busy
        onReply: (id, text) => root.sendReply(id, text)
        onReact: (id, key, on) => root.react(id, key, on)
        onStartPost: { root.posting = true; input.forceActiveFocus() }
    }

    ListView {
        id: list
        visible: root.tab === "" && !root.isChannel
        anchors { top: findBar.visible ? findBar.bottom : header.bottom; bottom: compose.top; left: parent.left; right: parent.right }
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
                readonly property var files: msg.modelData.files || []
                // Text shows unless the message is only a picture or only files.
                readonly property bool showBody: !imageOnly && (msg.modelData.deleted || (msg.modelData.text || "").length > 0)
                readonly property real bodyH: showBody ? body.implicitHeight : 0
                readonly property real picsTop: showBody ? body.y + body.implicitHeight + 8 : (bare ? 0 : 8)
                readonly property real picsH: imgs.length > 0 ? pics.implicitHeight : 0
                readonly property real filesTop: imgs.length > 0 ? picsTop + picsH + 8 : (showBody ? body.y + body.implicitHeight + 8 : 8)
                width: root.isChannel ? msg.maxBubble
                    : Math.min(msg.maxBubble, Math.max(showBody ? body.implicitWidth : 0, pics.implicitWidth, files.length > 0 ? fileCol.implicitWidth : 0) + 2 * pad)
                height: bare && files.length === 0 ? picsH
                    : files.length > 0 ? filesTop + fileCol.implicitHeight + 8
                    : imgs.length > 0 ? picsTop + picsH + (showBody ? 8.6 : 8)
                    : bodyH + 15.3
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
                    x: bubble.pad; y: bubble.picsTop
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
                    visible: bubble.showBody
                    x: bubble.pad; y: 6.7
                    width: Math.min(msg.maxBubble - 2 * bubble.pad, implicitWidth)
                    // Teams' 14/20 text.
                    lineHeight: 20; lineHeightMode: Text.FixedHeight
                    // Sanitised by the engine to a safe subset.
                    text: msg.modelData.deleted ? "This message has been deleted."
                        : "<style>a { color: " + theme.brand + "; text-decoration: none; } "
                          + ".mention { color: " + theme.brand + "; } "
                          + ".mention-me { color: " + theme.mentionMe + "; font-weight: 700; }</style>"
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
                // File cards, as Teams draws them: type icon, name, and
                // share/download actions in a 48 px header.
                Column {
                    id: fileCol
                    x: bubble.pad; y: bubble.filesTop
                    spacing: 8
                    Repeater {
                        model: bubble.files
                        Rectangle {
                            id: fc
                            required property var modelData
                            readonly property string t: (modelData.file_type || "").toLowerCase()
                            width: Math.min(318, msg.maxBubble - 2 * bubble.pad); height: 48
                            radius: 8
                            color: theme.searchFill
                            border.color: theme.divider
                            FluentIcon {
                                x: 13; anchors.verticalCenter: parent.verticalCenter; size: 32
                                name: ["png", "jpg", "jpeg", "gif", "bmp", "webp", "heic"].indexOf(fc.t) >= 0 ? "file-image-32"
                                    : ["mp4", "mov", "avi", "mkv", "webm"].indexOf(fc.t) >= 0 ? "file-video-32"
                                    : ["txt", "md", "log", "csv", "json", "xml"].indexOf(fc.t) >= 0 ? "file-text-32"
                                    : "file-32"
                                color: theme.textSecondary
                            }
                            Text {
                                x: 52; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 52 - 80
                                text: fc.modelData.name
                                elide: Text.ElideMiddle
                                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                                color: theme.text
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: Qt.openUrlExternally(fc.modelData.share_url || fc.modelData.object_url) }
                            }
                            Row {
                                anchors.right: parent.right; anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                Repeater {
                                    model: [{ icon: "share-20", label: "Open in browser" }, { icon: "download-20", label: "Download" }]
                                    Rectangle {
                                        required property var modelData
                                        width: 32; height: 32; radius: theme.radius
                                        color: fah.hovered ? theme.rowHover : "transparent"
                                        FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 20; color: theme.textStrong }
                                        HoverHandler { id: fah; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            onTapped: parent.modelData.icon === "download-20"
                                                ? backend.downloadFile(JSON.stringify(fc.modelData))
                                                : Qt.openUrlExternally(fc.modelData.share_url || fc.modelData.object_url)
                                        }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: modelData.label + " " + fc.modelData.name
                                    }
                                }
                            }
                            Accessible.role: Accessible.Link
                            Accessible.name: "File " + modelData.name
                        }
                    }
                }
            }
            // Teams marks a message that @mentions you with an "@" beside it.
            Text {
                visible: msg.modelData.mentions_me === true
                x: msg.mine ? bubble.x - width - 8 : bubble.x + bubble.width + 8
                y: bubble.y + (Math.min(bubble.height, 40) - height) / 2
                text: "@"
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
                color: theme.mentionMe
                Accessible.name: "Mentions you"
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
                        onTriggered: { root.editingId = msg.modelData.id; root.setPlain(msg.modelData.text); input.forceActiveFocus() }
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

    // The open tab: "" is Chat (or Posts); others replace the messages.
    property string tab: ""

    // Find in chat: matches among the loaded messages, newest first.
    property bool finding: false
    property int findIndex: 0
    readonly property var findHits: {
        const q = findField.text.trim().toLowerCase()
        if (!q) return []
        const shown = root.annotate(root.messages)
        const hits = []
        for (let i = 0; i < shown.length; i++) if ((shown[i].text || "").toLowerCase().indexOf(q) >= 0) hits.push(i)
        return hits
    }
    onFindHitsChanged: { findIndex = 0; if (findHits.length) list.positionViewAtIndex(findHits[0], ListView.Center) }
    Rectangle {
        id: findBar
        visible: root.finding && root.tab === ""
        anchors { top: header.bottom; left: parent.left; right: parent.right }
        height: visible ? 48 : 0
        color: theme.surface
        Rectangle {
            x: 72; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(420, parent.width - 144); height: 32; radius: theme.radius
            color: theme.input
            border.color: findField.activeFocus ? theme.brand : theme.stroke
            FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "search-20"; size: 16; color: theme.textSecondary }
            TextInput {
                id: findField
                x: 32; width: parent.width - 150
                anchors.verticalCenter: parent.verticalCenter
                font.family: theme.font; font.pixelSize: theme.base
                color: theme.text
                clip: true
                Keys.onReturnPressed: root.findNext(1)
                Keys.onEscapePressed: { text = ""; root.finding = false }
                Text { visible: !findField.text; text: "Find in chat"; color: theme.textTertiary; font: findField.font }
                Accessible.name: "Find in chat"
            }
            Text {
                anchors.right: findNav.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                visible: findField.text.length > 0
                text: root.findHits.length ? (root.findIndex + 1) + " of " + root.findHits.length : "No results"
                font.family: theme.font; font.pixelSize: theme.small
                color: theme.textSecondary
            }
            Row {
                id: findNav
                anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: [{ icon: "chevron-left-20", d: 1, l: "Older match" }, { icon: "chevron-right-20", d: -1, l: "Newer match" }]
                    Rectangle {
                        required property var modelData
                        width: 24; height: 24; radius: theme.radius
                        color: fnh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 16; color: theme.textStrong; rotation: 90 }
                        HoverHandler { id: fnh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.findNext(parent.modelData.d) }
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.l
                    }
                }
            }
        }
    }
    function findNext(d) {
        if (!findHits.length) return
        findIndex = (findIndex + d + findHits.length) % findHits.length
        list.positionViewAtIndex(findHits[findIndex], ListView.Center)
    }

    function channelFilesForTest() { return channelFiles }
    // A channel's Shared tab: its folder in the team's SharePoint library.
    ChannelFiles {
        id: channelFiles
        visible: root.isChannel && root.tab === "Shared"
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        teamId: root.teamId
        channelId: root.isChannel ? root.chatId : ""
        channelName: root.chatName
        reply: backend.channelFilesJson ? JSON.parse(backend.channelFilesJson) : ({})
        busy: backend.channelFilesBusy
        onLoad: (t, c, d, i) => backend.channelFilesLoad(t, c, d, i)
        onChange: (op, d, i, arg) => backend.channelFilesChange(op, d, i, arg)
    }
    // Shared: the files and links in this chat.
    Item {
        id: sharedPane
        visible: (root.tab === "Shared" && !root.isChannel) || root.tab === "Files"
        anchors { top: header.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
        readonly property var files: root.messages.reduce((a, m) => a.concat((m.files || []).map(f => Object.assign({ from: m.sender, time: m.time }, f))), []).reverse()
        readonly property var links: root.messages.reduce((a, m) => {
            const found = (m.html || "").match(/href="(https?:[^"]+)"/g) || []
            return a.concat(found.map(h => ({ url: h.slice(6, -1).replace(/&amp;/g, "&"), from: m.sender, time: m.time })))
        }, []).reverse()
        Flickable {
            anchors.fill: parent
            contentHeight: sharedCol.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: sharedCol
                x: 32; y: 20; width: parent.width - 64
                spacing: 8
                Text { text: "Files"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                Text {
                    visible: sharedPane.files.length === 0
                    text: "Files shared in this chat appear here."
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
                }
                Repeater {
                    model: sharedPane.files
                    Rectangle {
                        required property var modelData
                        width: sharedCol.width; height: 52; radius: theme.radius
                        color: sfh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "file-32"; size: 32; color: theme.textSecondary }
                        Column {
                            x: 52; anchors.verticalCenter: parent.verticalCenter
                            Text { text: parent.parent.modelData.name; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                            Text { text: parent.parent.modelData.from + " · " + root.stamp(parent.parent.modelData.time); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: theme.radius
                            color: sdh.hovered ? theme.selected : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: "download-20"; size: 20; color: theme.textStrong }
                            HoverHandler { id: sdh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: backend.downloadFile(JSON.stringify(parent.parent.modelData)) }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Download " + parent.modelData.name
                        }
                        HoverHandler { id: sfh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Qt.openUrlExternally(modelData.share_url || modelData.object_url) }
                    }
                }
                Item { width: 1; height: 16 }
                Text { text: "Links"; font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text }
                Text {
                    visible: sharedPane.links.length === 0
                    text: "Links shared in this chat appear here."
                    font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
                }
                Repeater {
                    model: sharedPane.links
                    Rectangle {
                        required property var modelData
                        width: sharedCol.width; height: 44; radius: theme.radius
                        color: slh.hovered ? theme.rowHover : "transparent"
                        Column {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 24
                            Text { width: parent.width; text: parent.parent.modelData.url; elide: Text.ElideRight; font.family: theme.font; font.pixelSize: theme.base; color: theme.brand }
                            Text { text: parent.parent.modelData.from + " · " + root.stamp(parent.parent.modelData.time); font.family: theme.font; font.pixelSize: theme.small; color: theme.textSecondary }
                        }
                        HoverHandler { id: slh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Qt.openUrlExternally(modelData.url) }
                    }
                }
            }
        }
    }
    // Tabs OST can't offer say so.
    Column {
        visible: ["Notes", "Recap", "Storyline"].indexOf(root.tab) >= 0
        anchors.centerIn: parent
        spacing: 8
        FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "info-16"; size: 32; color: theme.textSecondary }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.tab + " isn't available in OST yet."
            font.family: theme.font; font.pixelSize: theme.base; color: theme.textSecondary
        }
    }

    // Participants: who is in this chat.
    Rectangle {
        id: participants
        visible: false
        z: 50
        anchors { top: header.bottom; right: parent.right; topMargin: 4; rightMargin: 16 }
        width: 300; height: Math.min(400, partCol.implicitHeight + 24)
        radius: 8
        color: theme.menu
        border.color: theme.dividerSoft
        readonly property var members: {
            const seen = {}, out = []
            if (root.myName) { out.push({ name: root.myName + " (You)", mri: "me" }); seen.me = true }
            for (const m of root.messages) {
                if (m.mine || !m.sender_mri || seen[m.sender_mri]) continue
                seen[m.sender_mri] = true
                out.push({ name: m.sender, mri: m.sender_mri })
            }
            if (!root.isChannel && root.chatPhotoId && !seen[root.chatPhotoId] && !root.isSelf) out.push({ name: root.chatName, mri: root.chatPhotoId })
            return out
        }
        Column {
            id: partCol
            x: 12; y: 12; width: parent.width - 24
            spacing: 4
            Text {
                text: root.isChannel ? "People in this channel" : "People (" + participants.members.length + ")"
                font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold; color: theme.text
            }
            Repeater {
                model: participants.members
                Item {
                    required property var modelData
                    width: partCol.width; height: 40
                    Avatar {
                        x: 0; anchors.verticalCenter: parent.verticalCenter; size: 32
                        name: parent.modelData.name.replace(/ \(You\)$/, "")
                        photoId: parent.modelData.mri
                        presence: parent.modelData.mri === root.chatPhotoId ? root.chatPresence : ""
                    }
                    Text {
                        x: 44; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 44; elide: Text.ElideRight
                        text: parent.modelData.name
                        font.family: theme.font; font.pixelSize: theme.base; color: theme.text
                    }
                }
            }
        }
    }

    // Format (Teams' format bar): wrap the selection in a style or a list.
    property bool formatting: false
    function wrapSelection(tag) {
        const a = input.selectionStart, b = input.selectionEnd
        if (a === b) return
        const sel = root.escapeHtml(input.getText(a, b))
        input.remove(a, b)
        const html = tag === "ul" || tag === "ol" ? "<" + tag + "><li>" + sel.replace(/<br>/g, "</li><li>") + "</li></" + tag + ">"
            : "<" + tag + ">" + sel + "</" + tag + ">"
        input.insert(a, html)
        input.forceActiveFocus()
    }
    // Files picked to send with the next message (local paths).
    property var pendingFiles: []
    function addFiles(urls) {
        const paths = urls.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, "")))
        pendingFiles = pendingFiles.concat(paths.filter(p => pendingFiles.indexOf(p) < 0))
    }
    // Send what's in the compose box: text, files, or both.
    function sendCompose() {
        if (root.pendingFiles.length > 0) {
            backend.sendFiles(root.pendingFiles.join("\n"), root.plainText())
            root.pendingFiles = []
        } else if (root.plainText().trim().length > 0) {
            // Formatted text goes as Teams HTML; plain text as before.
            const html = input.getFormattedText(0, input.length)
            if (/font-weight:\s*[6-9]00|font-style:\s*italic|text-decoration:[^;"]*(underline|line-through)|<ul|<ol/.test(html)) backend.sendRich(html)
            else root.send(root.plainText())
        }
        input.clear()
        root.formatting = false
        root.posting = false
    }
    EmojiPicker {
        id: emojiPicker
        parent: compose
        x: compose.width - width; y: -height - 8
        onPicked: e => { input.insert(input.cursorPosition, e); close(); input.forceActiveFocus() }
    }
    FileDialog {
        id: filePicker
        title: "Upload from this device"
        fileMode: FileDialog.OpenFiles
        onAccepted: root.addFiles(selectedFiles)
    }

    // Compose box
    Rectangle {
        id: compose
        visible: root.chatName.length > 0 && (!root.isChannel || root.posting)
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.leftMargin: root.pane ? 12 : 72; anchors.rightMargin: root.pane ? 12 : 72; anchors.bottomMargin: root.pane ? 12 : 24
        height: Math.max(44, input.contentHeight + 24) + (root.pendingFiles.length > 0 ? pendingRow.height + 8 : 0)
            + (root.formatting ? 40 : 0)
        // The format bar: bold, italic, underline, strikethrough, lists.
        Row {
            visible: root.formatting
            x: 8; y: 4
            spacing: 2
            Repeater {
                model: [
                    { icon: "text-bold-20", tag: "b", label: "Bold (Ctrl+B)" },
                    { icon: "text-italic-20", tag: "i", label: "Italic (Ctrl+I)" },
                    { icon: "text-underline-20", tag: "u", label: "Underline (Ctrl+U)" },
                    { icon: "text-strike-20", tag: "s", label: "Strikethrough" },
                    { icon: "text-bullets-20", tag: "ul", label: "Bulleted list" },
                    { icon: "text-numbers-20", tag: "ol", label: "Numbered list" },
                ]
                Rectangle {
                    required property var modelData
                    width: 32; height: 32; radius: theme.radius
                    color: fbh.hovered ? theme.rowHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: parent.modelData.icon; size: 20; color: theme.textStrong }
                    HoverHandler { id: fbh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.wrapSelection(parent.modelData.tag) }
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                }
            }
        }
        // Files waiting to be sent, as removable chips above the text.
        Flow {
            id: pendingRow
            visible: root.pendingFiles.length > 0
            x: 12; y: root.formatting ? 44 : 8; width: parent.width - 24
            spacing: 8
            Repeater {
                model: root.pendingFiles
                Rectangle {
                    required property string modelData
                    height: 40; width: Math.min(300, nameText.implicitWidth + 80)
                    radius: 8
                    color: theme.searchFill
                    border.color: theme.divider
                    FluentIcon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "file-32"; size: 24; color: theme.textSecondary }
                    Text {
                        id: nameText
                        x: 40; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 76
                        text: parent.modelData.split("/").pop()
                        elide: Text.ElideMiddle
                        font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                        color: theme.text
                    }
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24; radius: theme.radius
                        color: rmh.hovered ? theme.rowHover : "transparent"
                        FluentIcon { anchors.centerIn: parent; name: "dismiss-12"; size: 12; color: theme.textStrong }
                        HoverHandler { id: rmh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.pendingFiles = root.pendingFiles.filter(p => p !== parent.parent.modelData) }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Remove " + parent.modelData.split("/").pop()
                    }
                }
            }
        }
        radius: theme.radius
        color: theme.input
        border.color: input.activeFocus ? theme.brand : theme.divider
        TextArea {
            id: input
            anchors { left: parent.left; right: tools.left; bottom: parent.bottom; bottomMargin: (44 - 32) / 2 }
            anchors.leftMargin: 4
            placeholderText: root.isChannel ? "Start a post" : "Type a message"
            placeholderTextColor: theme.textSecondary
            font.family: theme.font; font.pixelSize: theme.base
            color: theme.text
            wrapMode: TextArea.Wrap
            background: null
            textFormat: TextEdit.RichText
            Keys.onPressed: event => {
                if (!(event.modifiers & Qt.ControlModifier)) return
                if (event.key === Qt.Key_B) { root.wrapSelection("b"); event.accepted = true }
                else if (event.key === Qt.Key_I) { root.wrapSelection("i"); event.accepted = true }
                else if (event.key === Qt.Key_U) { root.wrapSelection("u"); event.accepted = true }
                else if (event.key === Qt.Key_X && (event.modifiers & Qt.AltModifier)) { root.wrapSelection("s"); event.accepted = true }
            }
            onActiveFocusChanged: if (activeFocus) enterKey = backend.setting("enterKey") || "send"
            onTextChanged: {
                if (length > 0) root.typing()
                draftSave.restart()
            }
            // Settings > Chats and channels: Enter sends (Shift+Enter breaks the
            // line), or Enter breaks the line and Ctrl+Enter sends.
            property string enterKey: backend.setting("enterKey") || "send"
            Keys.onReturnPressed: event => {
                const sendKey = enterKey === "newline" ? (event.modifiers & Qt.ControlModifier) : !(event.modifiers & Qt.ShiftModifier)
                if (!sendKey) { event.accepted = false; return }
                if (root.editingId) { root.editMessage(root.editingId, root.plainText()); root.editingId = ""; input.clear() }
                else root.sendCompose()
            }
            Keys.onEscapePressed: {
                if (root.editingId) { root.editingId = ""; input.clear() }
                else if (root.posting) root.posting = false
            }
        }
        Row {
            id: tools
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.bottom: parent.bottom; anchors.bottomMargin: 12
            spacing: 12
            FluentIcon {
                name: "format-20"
                color: root.formatting ? theme.brand : theme.icon
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.formatting = !root.formatting }
                Accessible.role: Accessible.Button
                Accessible.name: "Format"
            }
            FluentIcon {
                id: emojiButton
                name: "emoji-20"
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: emojiPicker.open() }
                Accessible.role: Accessible.Button
                Accessible.name: "Emoji"
            }
            FluentIcon {
                name: "attach-20"
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: filePicker.open() }
                Accessible.role: Accessible.Button
                Accessible.name: "Attach files"
            }
            FluentIcon {
                name: "add-20"
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: actionsMenu.open() }
                Accessible.role: Accessible.Button
                Accessible.name: "Actions and apps"
                MenuPopup {
                    id: actionsMenu
                    x: -width + 20; y: -height - 12
                    items: [{ label: "Upload from this device", icon: "attach-20" }, { label: "Emoji", icon: "emoji-20" }]
                    onPicked: i => i === 0 ? filePicker.open() : emojiPicker.open()
                }
            }
            Rectangle { width: 1; height: 20; color: theme.divider }
            FluentIcon {
                readonly property bool ready: input.length > 0 || root.pendingFiles.length > 0
                name: ready ? "send-20-filled" : "send-20"
                color: ready ? theme.brand : theme.icon
                TapHandler { onTapped: root.sendCompose() }
                Accessible.role: Accessible.Button
                Accessible.name: "Send"
            }
        }
    }
}
