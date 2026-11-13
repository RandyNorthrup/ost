import QtQuick
import QtQuick.Controls.Basic

// The Details pane of Teams' Files apps (OneDrive's, docs/spec/details-pane.md):
// 304 wide at the list's right, one scrolling column of white cards on
// #FAFAFA, 12 apart: the header (type icon, name, Options, Dismiss), the
// 320 x 180 picture, Has access, the activity feed (All activity /
// Comments, the bell, the comment box, the dated groups) and More details.
Rectangle {
    id: root
    /// The item (a drive item from the list) and its loaded details.
    property var item: null
    /// With nothing selected, the folder shown ({name, drive_id, item_id}):
    /// its name and its activity only.
    property var folder: null
    readonly property bool folderMode: !item && !!folder
    property var info: null
    property bool loading: false
    property string error: ""
    /// The list's FileActions: the menu, share dialog and Manage access.
    property var actions: null
    signal dismissed()
    color: theme.pick("#FAFAFA", "#1F1F1F")
    readonly property color ink: theme.pick("#616161", "#D6D6D6")
    readonly property color strong: theme.pick("#424242", "#D6D6D6")
    readonly property color brand: theme.pick("#5B5FC7", "#7F85F5")
    readonly property color card: theme.surface
    readonly property string tag: "dp" + Math.floor(Math.random() * 1e9) + ":"
    property bool commentsOnly: false
    readonly property var feed: !info ? [] : (info.details.activities || []).filter(a => !commentsOnly || a.kind === "comment")
    property bool notify: true

    function load() {
        loading = true; error = ""
        if (item) backend.driveAction(tag + "details", JSON.stringify(item), "{}")
        else if (folder) backend.driveAction(tag + "folder_details", "{}", JSON.stringify({ drive_id: folder.drive_id || "", item_id: folder.item_id || "" }))
        else loading = false
    }
    onItemChanged: { info = null; load() }
    onFolderChanged: if (!item) { info = null; load() }
    Connections {
        target: backend
        function onDriveActionDone(op, result, err) {
            if (!op.startsWith(root.tag)) return
            const kind = op.slice(root.tag.length)
            if (kind === "folder_details") {
                root.loading = false; root.error = err || ""
                root.info = err ? null : { details: { activities: JSON.parse(result).activities } }
            } else if (kind === "details") {
                root.loading = false; root.error = err || ""
                root.info = err ? null : JSON.parse(result)
                if (root.info) root.notify = root.info.details.notify
            } else if (kind === "comment") {
                sending = false
                if (err) commentError = err
                else { commentBox.text = ""; root.load() }
            } else if (kind === "delete_comment") {
                if (err) root.commentError = err
                else root.load()
            } else if (kind === "edit_comment" || kind === "reply_comment") {
                root.sending = false
                if (err) root.commentError = err
                else { root.editingId = ""; root.load() }
            } else if (kind === "notify") {
                root.notifyError = err ? "Notifications couldn't be turned " + (root.notify ? "on" : "off") + ". " + err : ""
                if (err) root.notify = !root.notify
            }
        }
    }
    property bool sending: false
    /// The comment being edited (its card becomes the edit box).
    property string editingId: ""
    function sendEdit(id, text) {
        if (!text.trim() || sending) return
        sending = true; commentError = ""
        backend.driveAction(tag + "edit_comment", JSON.stringify(item), JSON.stringify({ id: id, text: text.trim() }))
    }
    function sendReply(id, text) {
        if (!text.trim() || sending) return false
        sending = true; commentError = ""
        backend.driveAction(tag + "reply_comment", JSON.stringify(item), JSON.stringify({ id: id, text: text.trim() }))
        return true
    }
    property string notifyError: ""
    property string commentError: ""

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.height + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Column {
            id: col
            width: root.width
            spacing: 12

            // Header: 62.67 tall, the 20 px type icon at 16, the name
            // (14/600) 28 after it, Options (32) and Dismiss (24).
            Rectangle {
                width: parent.width; height: 62.67; color: root.card
                FluentIcon {
                    x: 16; y: 21.33; size: 20
                    name: root.folderMode || (root.item && root.item.is_folder) ? "ft-folder-32" : root.item ? root.icon20(root.item.kind) : ""
                }
                Text {
                    x: 44; y: 21.33; width: parent.width - 44 - 80
                    text: root.item ? root.item.name : root.folder ? root.folder.name : ""
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
                Rectangle {
                    id: optionsButton
                    visible: !root.folderMode
                    x: parent.width - 16 - 24 - 8 - 32; y: 15.67; width: 32; height: 31.33; radius: 4
                    color: oph.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "more-horizontal-20"; size: 20; color: root.strong }
                    HoverHandler { id: oph; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: if (root.actions && root.item) root.actions.popup(root.item, optionsButton, 0, optionsButton.height) }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Options"
                }
                Rectangle {
                    x: parent.width - 16 - 24; y: 19.33; width: 24; height: 24; radius: 4
                    color: dsh.hovered ? theme.menuHover : "transparent"
                    FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: root.ink }
                    HoverHandler { id: dsh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.dismissed() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Dismiss"
                }
            }
            // The picture: 304 x 180.
            Rectangle {
                visible: !root.folderMode
                width: parent.width; height: 180; color: root.card; clip: true
                Image {
                    width: 320; height: 180
                    source: root.info ? root.info.thumbnail : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            // Has access: Add people, the people, the link circle; Manage access.
            Rectangle {
                visible: !root.folderMode
                width: parent.width; height: 114.67; radius: 4; color: root.card
                Text { x: 16; y: 16; text: "Has access"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.ink; Accessible.role: Accessible.Heading; Accessible.name: text }
                Row {
                    x: 16; y: 42.67; spacing: 8
                    Rectangle {
                        width: 32; height: 32; radius: 16; color: root.brand
                        FluentIcon { anchors.centerIn: parent; name: "person-add-20"; size: 20; color: "white" }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: if (root.actions && root.item) { root.actions.item = root.item; root.actions.act("Share") } }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Add people"
                    }
                    Repeater {
                        model: root.info ? root.info.people : []
                        Avatar {
                            required property var modelData
                            size: 32; name: modelData.name; photoId: modelData.oid
                            Accessible.name: modelData.name
                        }
                    }
                    Rectangle {
                        visible: !!root.info && root.info.links
                        width: 32; height: 32; radius: 16; color: theme.pick("#D7D4D4", "#5C5C5C")
                        FluentIcon { anchors.centerIn: parent; name: "link-20"; size: 20; color: theme.pick("#444241", "#E0E0E0") }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.manage() }
                        Accessible.role: Accessible.Button
                        Accessible.name: "Shared via link, manage access"
                    }
                }
                Text {
                    x: 16; y: 82.67
                    text: "Manage access"
                    font.family: theme.font; font.pixelSize: 12; color: theme.pick("#3D3E66", "#C5C7FA")
                    font.underline: mah.hovered
                    HoverHandler { id: mah; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.manage() }
                    Accessible.role: Accessible.Button
                    Accessible.name: text
                }
            }
            // Activity
            Rectangle {
                width: parent.width; height: actCol.height + 28; color: root.card
                Column {
                    id: actCol
                    x: 16; y: 16; width: parent.width - 32
                    spacing: 0
                    // A folder: "Activity" only (no view switch, bell or comments).
                    Text {
                        visible: root.folderMode
                        height: 32; verticalAlignment: Text.AlignVCenter
                        text: "Activity"
                        font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold; color: root.ink
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }
                    Row {
                        visible: !root.folderMode
                        spacing: 0; height: 32
                        Item {
                            width: 94.1; height: 32
                            Row {
                                x: 4; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                Text { text: root.commentsOnly ? "Comments" : "All activity"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.brand }
                                FluentIcon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down-12"; size: 12; color: root.brand }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: viewMenu.open() }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Activity feed view options. Selected view option is " + (root.commentsOnly ? "Comments" : "All activity")
                            MenuPopup {
                                id: viewMenu
                                fabric: true; fabricWidth: 232
                                y: parent.height + 4
                                items: [{ label: "All activity", checked: !root.commentsOnly }, { label: "Comments", checked: root.commentsOnly }]
                                onPicked: i => root.commentsOnly = i === 1
                            }
                        }
                        Rectangle {
                            width: 32; height: 31.33; radius: 4
                            color: bh.hovered ? theme.menuHover : "transparent"
                            FluentIcon { anchors.centerIn: parent; name: root.notify ? "alert-20" : "alert-off-20"; size: 20; color: root.brand }
                            HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    root.notify = !root.notify
                                    backend.driveAction(root.tag + "notify", JSON.stringify(root.item), JSON.stringify({ on: root.notify }))
                                }
                            }
                            Accessible.role: Accessible.CheckBox
                            Accessible.checked: root.notify
                            Accessible.name: root.notify ? "Notifications for item activity. Select to turn off notifications"
                                : "Notifications for item activity. Select to turn on notifications"
                        }
                    }
                    Text {
                        visible: !!root.notifyError
                        width: parent.width; bottomPadding: 4; wrapMode: Text.Wrap
                        text: root.notifyError
                        font.family: theme.font; font.pixelSize: 12; color: theme.danger
                    }
                    Item { width: 1; height: 8 }
                    // The comment box: 272 x 32, Cancel and Submit comment.
                    Rectangle {
                        visible: !root.commentsDisabled && !root.folderMode
                        width: parent.width; height: 32; radius: 4
                        color: theme.surface
                        border.width: 0.67; border.color: commentBox.activeFocus ? root.brand : theme.pick("#D1D1D1", "#666666")
                        TextInput {
                            id: commentBox
                            x: 8; width: parent.width - 8 - 74; anchors.verticalCenter: parent.verticalCenter
                            font.family: theme.font; font.pixelSize: 14; color: root.ink; clip: true
                            maximumLength: 2000
                            onTextChanged: root.commentError = text.length >= 2000 ? "Maximum character limit exceeded" : ""
                            Keys.onReturnPressed: root.send()
                            Text { visible: !commentBox.text; text: "Add a comment"; color: theme.textTertiary; font: commentBox.font }
                            Accessible.name: "Comment input"
                        }
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 10; height: 32
                            Rectangle {
                                width: 32; height: 32; radius: 4; color: "transparent"
                                FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: theme.pick("#7F85F5", "#7F85F5") }
                                TapHandler { onTapped: { commentBox.text = ""; root.commentError = "" } }
                                Accessible.role: Accessible.Button
                                Accessible.name: "Cancel"
                            }
                            Rectangle {
                                width: 32; height: 32; radius: 4; color: "transparent"
                                FluentIcon { anchors.centerIn: parent; name: "send-16"; size: 16; color: commentBox.text.trim() ? root.brand : theme.pick("#BDBDBD", "#5C5C5C") }
                                HoverHandler { cursorShape: commentBox.text.trim() ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                TapHandler { onTapped: root.send() }
                                Accessible.role: Accessible.Button
                                Accessible.name: "Submit comment"
                            }
                        }
                    }
                    Text {
                        visible: !!root.commentError
                        width: parent.width; topPadding: 4; wrapMode: Text.Wrap
                        text: root.commentError
                        font.family: theme.font; font.pixelSize: 12; color: theme.danger
                    }
                    Item { width: 1; height: 16 }
                    // The activities, by date group: a 12/600 heading, then
                    // #FAFAFA cards (radius 4, padding 14 16, 8 apart).
                    Repeater {
                        model: root.feed
                        Column {
                            required property var modelData
                            required property int index
                            readonly property bool first: index === 0 || root.feed[index - 1].group !== modelData.group
                            width: actCol.width
                            spacing: 0
                            Item { visible: parent.first && parent.index > 0; width: 1; height: 8 }
                            Text {
                                visible: parent.first
                                height: 24; text: parent.modelData.group
                                font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: root.strong
                                Accessible.role: Accessible.Heading
                                Accessible.name: text
                            }
                            // A comment (OneDrive's comment card): the author's
                            // 32 px picture, the name, the comment (padding 4 0 6),
                            // the time, and Show actions (Delete comment).
                            // Edit comment: a 272 x 68 box (2 px brand border)
                            // with the text, Cancel and Submit comment.
                            Rectangle {
                                visible: !!parent.modelData.comment_id && root.editingId === parent.modelData.comment_id
                                width: parent.width; height: visible ? Math.max(68, editText.contentHeight + 12 + 36) : 0
                                radius: 2; color: theme.surface
                                border.width: 2; border.color: root.brand
                                TextEdit {
                                    id: editText
                                    x: 8; y: 6; width: parent.width - 16
                                    wrapMode: TextEdit.Wrap; selectByMouse: true
                                    font.family: theme.font; font.pixelSize: 14; color: root.ink
                                    Keys.onEscapePressed: root.editingId = ""
                                    Accessible.role: Accessible.EditableText
                                    Accessible.name: "Comment input"
                                }
                                Row {
                                    anchors.right: parent.right; anchors.rightMargin: 6; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                                    Rectangle {
                                        width: 32; height: 32; radius: 4; color: ech.hovered ? theme.menuHover : "transparent"
                                        FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: root.brand }
                                        HoverHandler { id: ech; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.editingId = "" }
                                        ToolTip.visible: ech.hovered; ToolTip.text: "Cancel"; ToolTip.delay: 300
                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Cancel"
                                    }
                                    Rectangle {
                                        width: 32; height: 32; radius: 4; color: esh.hovered ? theme.menuHover : "transparent"
                                        FluentIcon { anchors.centerIn: parent; name: "send-16"; size: 16; color: editText.text.trim() ? root.brand : theme.pick("#BDBDBD", "#5C5C5C") }
                                        HoverHandler { id: esh; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: root.sendEdit(root.editingId, editText.text) }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Submit comment"
                                    }
                                }
                                onVisibleChanged: if (visible) { editText.text = parent.modelData.source || ""; editText.cursorPosition = editText.text.length; editText.forceActiveFocus() }
                            }
                            Rectangle {
                                id: ccard
                                visible: !!parent.modelData.comment_id && root.editingId !== parent.modelData.comment_id
                                readonly property var c: parent.modelData
                                width: parent.width; height: visible ? cText.y + cText.height + 6 + 18 + 14 : 0
                                radius: 4; color: theme.pick("#FAFAFA", "#292929")
                                Avatar { x: 16; y: 22; size: 32; name: ccard.c.mine ? root.myName : ccard.c.author; photoId: root.info && root.info.oids ? (root.info.oids[(ccard.c.author_email || "").toLowerCase()] || "") : "" }
                                Text { x: 64; y: 14; width: parent.width - 64 - 40; height: 16; elide: Text.ElideRight; text: ccard.c.author; font.family: theme.font; font.pixelSize: 12; color: root.strong }
                                Text {
                                    id: cText
                                    x: 64; y: 30 + 4; width: parent.width - 64 - 16
                                    wrapMode: Text.Wrap; textFormat: Text.StyledText
                                    text: ccard.c.text
                                    font.family: theme.font; font.pixelSize: 12; color: root.ink
                                }
                                Text {
                                    x: 64; y: cText.y + cText.height + 6 + 2
                                    // OneDrive's "{0} • Edited".
                                    text: ccard.c.time + (ccard.c.edited ? " \u2022 Edited" : "")
                                    font.family: theme.font; font.pixelSize: 10; color: root.strong
                                    HoverHandler { id: ctth }
                                    ToolTip.visible: ctth.hovered
                                    ToolTip.text: ccard.c.tip
                                    ToolTip.delay: 500
                                }
                                Rectangle {
                                    visible: ccard.c.mine
                                    x: parent.width - 38; y: 6; width: 32; height: 32; radius: 4
                                    color: cah.hovered ? theme.menuHover : "transparent"
                                    FluentIcon { anchors.centerIn: parent; name: "more-horizontal-16"; size: 16; color: root.brand }
                                    HoverHandler { id: cah; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: cmenu.open() }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: "Show actions"
                                    MenuPopup {
                                        id: cmenu
                                        fabric: true
                                        x: parent.width - width; y: parent.height + 4
                                        items: [{ label: "Edit comment", icon: "edit-16" }, { label: "Delete comment", icon: "delete-16" }]
                                        onPicked: i => {
                                            if (i === 0) root.editingId = ccard.c.comment_id
                                            else { deleteComment.target = ccard.c.comment_id; deleteComment.open() }
                                        }
                                    }
                                }
                                Accessible.role: Accessible.ListItem
                                Accessible.name: ccard.c.author + ": " + ccard.c.text + " " + ccard.c.time
                            }
                            // Replies, 8 in and 256 wide (padding 8 8 8 24): the
                            // 32 px picture, "You replied" / "{name} replied",
                            // the text and the time.
                            Item { visible: !!parent.modelData.comment_id && (parent.modelData.replies || []).length > 0; width: 1; height: 8 }
                            Repeater {
                                model: parent.modelData.comment_id ? (parent.modelData.replies || []) : []
                                Item {
                                    required property var modelData
                                    x: 8; width: actCol.width - 16; height: rText.y + rText.height + 2 + 18 + 8
                                    Avatar { x: 24; y: 16; size: 32; name: parent.modelData.mine ? root.myName : parent.modelData.author; photoId: root.info && root.info.oids ? (root.info.oids[(parent.modelData.author_email || "").toLowerCase()] || "") : "" }
                                    Text { x: 72; y: 8; width: parent.width - 72 - 8; height: 16; elide: Text.ElideRight; text: parent.modelData.author + " replied"; font.family: theme.font; font.pixelSize: 12; color: root.strong }
                                    Text {
                                        id: rText
                                        x: 72; y: 24 + 4; width: parent.width - 72 - 8
                                        wrapMode: Text.Wrap; textFormat: Text.StyledText
                                        text: parent.modelData.text
                                        font.family: theme.font; font.pixelSize: 12; color: root.ink
                                    }
                                    Text { x: 72; y: rText.y + rText.height + 4; text: parent.modelData.time + (parent.modelData.edited ? " \u2022 Edited" : ""); font.family: theme.font; font.pixelSize: 10; color: root.strong }
                                    Accessible.role: Accessible.ListItem
                                    Accessible.name: parent.modelData.author + " replied: " + parent.modelData.text + " " + parent.modelData.time
                                }
                            }
                            // The Reply box under each comment: 256 x 32 on
                            // white, padding 8; Cancel and Submit comment.
                            Item {
                                visible: !!parent.modelData.comment_id && root.editingId !== parent.modelData.comment_id && !root.commentsDisabled
                                width: parent.width; height: visible ? 48 : 0
                                readonly property string cid: parent.modelData.comment_id || ""
                                Rectangle {
                                    x: 8; y: 8; width: 256; height: 32; radius: 4
                                    color: theme.surface
                                    border.width: 0.67; border.color: replyBox.activeFocus ? root.brand : theme.pick("#D1D1D1", "#666666")
                                    TextInput {
                                        id: replyBox
                                        x: 12; width: parent.width - 12 - 72; anchors.verticalCenter: parent.verticalCenter
                                        clip: true; maximumLength: 2000
                                        font.family: theme.font; font.pixelSize: 14; color: root.ink
                                        Text { visible: !replyBox.text; text: "Reply"; color: theme.textTertiary; font: replyBox.font }
                                        Keys.onReturnPressed: if (root.sendReply(parent.parent.cid, text)) text = ""
                                        Accessible.role: Accessible.EditableText
                                        Accessible.name: "Comment input"
                                    }
                                    Rectangle {
                                        x: parent.width - 72; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 4
                                        color: rch.hovered ? theme.menuHover : "transparent"
                                        FluentIcon { anchors.centerIn: parent; name: "dismiss-16"; size: 16; color: root.brand }
                                        HoverHandler { id: rch; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: replyBox.text = "" }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Cancel"
                                    }
                                    Rectangle {
                                        x: parent.width - 36; anchors.verticalCenter: parent.verticalCenter; width: 32; height: 32; radius: 4
                                        color: rsh.hovered ? theme.menuHover : "transparent"
                                        FluentIcon { anchors.centerIn: parent; name: "send-16"; size: 16; color: replyBox.text.trim() ? root.brand : theme.pick("#BDBDBD", "#5C5C5C") }
                                        HoverHandler { id: rsh; cursorShape: replyBox.text.trim() ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                        TapHandler { onTapped: if (root.sendReply(parent.parent.parent.cid, replyBox.text)) replyBox.text = "" }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Submit comment"
                                    }
                                }
                            }
                            Rectangle {
                                visible: !parent.modelData.comment_id
                                width: parent.width; height: visible ? actText.height + timeText.height + 28 + 2 : 0
                                radius: 4; color: theme.pick("#FAFAFA", "#292929")
                                FluentIcon { x: 24; y: (parent.height - 16) / 2; size: 16; color: root.brand; name: root.activityIcon(parent.parent.modelData.kind) }
                                Text {
                                    id: actText
                                    x: 64; y: 14; width: parent.width - 64 - 16
                                    wrapMode: Text.Wrap; textFormat: Text.StyledText
                                    text: parent.parent.modelData.text
                                    font.family: theme.font; font.pixelSize: 12; color: root.ink
                                }
                                Text {
                                    id: timeText
                                    x: 64; y: actText.y + actText.height + 2
                                    text: parent.parent.modelData.time
                                    font.family: theme.font; font.pixelSize: 10; color: root.strong
                                    HoverHandler { id: tth }
                                    ToolTip.visible: tth.hovered
                                    ToolTip.text: parent.parent.modelData.tip
                                    ToolTip.delay: 500
                                }
                                Accessible.role: Accessible.ListItem
                                Accessible.name: parent.modelData.text.replace(/<[^>]+>/g, "") + " " + parent.modelData.time
                            }
                            Item { width: 1; height: 8 }
                        }
                    }
                    Text {
                        visible: !!root.info && root.feed.length === 0 && root.commentsOnly
                        text: "This item has no comments."
                        font.family: theme.font; font.pixelSize: 12; color: root.ink
                    }
                }
            }
            // More details: label (14/20 600) over value (14/20), 12 apart.
            Rectangle {
                width: parent.width; height: detCol.height + 32; radius: 4; color: root.card
                visible: !!root.info && !root.folderMode
                Column {
                    id: detCol
                    x: 16; y: 16; width: parent.width - 32
                    spacing: 12
                    Repeater {
                        model: !root.info || root.folderMode ? [] : [
                            { label: "Type", value: root.info.details.type_text },
                            { label: "Modified", value: root.info.details.modified },
                            { label: "Date created", value: root.info.details.created },
                            { label: "Path", value: root.info.details.path.join(" › "), copy: true },
                            { label: "Size", value: root.item && !root.item.is_folder ? root.size(root.item.size) : "" }
                        ].filter(r => !!r.value)
                        Column {
                            required property var modelData
                            width: detCol.width
                            Row {
                                height: modelData.copy ? 31.33 : 20
                                spacing: 0
                                Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.label; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: root.strong }
                                Rectangle {
                                    visible: !!modelData.copy
                                    width: 32; height: 31.33; radius: 4
                                    color: cph.hovered ? theme.menuHover : "transparent"
                                    FluentIcon { anchors.centerIn: parent; name: "copy-20"; size: 20; color: root.strong }
                                    HoverHandler { id: cph; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: if (root.actions) root.actions.copy(root.info.direct_url || (root.item ? root.item.web_url : "")) }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: "Copy direct link"
                                }
                            }
                            Text {
                                width: parent.width; wrapMode: Text.Wrap
                                text: modelData.value
                                font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: root.ink
                            }
                        }
                    }
                }
            }
        }
    }
    BusyIndicator { anchors.centerIn: parent; running: root.loading && !root.info; visible: running }
    Text {
        visible: !!root.error && !root.info
        anchors.centerIn: parent; width: root.width - 32
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
        text: root.error
        font.family: theme.font; font.pixelSize: 14; color: theme.danger
    }

    // OneDrive's "Delete comment" question: Yes / Cancel.
    Popup {
        id: deleteComment
        property string target: ""
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        modal: true; focus: true; padding: 24
        width: 440
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
        background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
        contentItem: Column {
            spacing: 20
            Text { text: "Delete comment"; font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; color: root.ink; Accessible.role: Accessible.Heading; Accessible.name: text }
            Text { width: 392; wrapMode: Text.Wrap; text: "Do you want to delete this comment?"; font.family: theme.font; font.pixelSize: 14; color: root.ink }
            Row {
                anchors.right: parent.right; spacing: 8
                Rectangle {
                    width: 80; height: 32; radius: 4; color: dyh.hovered ? theme.brandHover : theme.brandFill
                    Text { anchors.centerIn: parent; text: "Yes"; color: "white"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                    HoverHandler { id: dyh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { deleteComment.close(); backend.driveAction(root.tag + "delete_comment", JSON.stringify(root.item), JSON.stringify({ id: deleteComment.target })) } }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Yes"
                }
                Rectangle {
                    width: 80; height: 32; radius: 4; color: theme.surface; border.width: 0.67; border.color: theme.pick("#D1D1D1", "#666666")
                    Text { anchors.centerIn: parent; text: "Cancel"; color: root.ink; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: deleteComment.close() }
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"
                }
            }
        }
    }
    readonly property string myName: backend.userName || ""
    readonly property bool commentsDisabled: !!info && info.details.comments_disabled
    function send() {
        const t = commentBox.text.trim()
        if (!t || sending) return
        sending = true; commentError = ""
        backend.driveAction(tag + "comment", JSON.stringify(item), JSON.stringify({ text: t }))
    }
    function manage() { if (actions && item) { actions.item = item; actions.act("Manage access") } }
    function icon20(kind) {
        const k = String(kind || "").toLowerCase()
        const m = { doc: "docx", docx: "docx", xls: "xlsx", xlsx: "xlsx", ppt: "pptx", pptx: "pptx", pdf: "pdf", txt: "txt", one: "one", loop: "loop",
                    png: "photo", jpg: "photo", jpeg: "photo", gif: "photo" }[k]
        return m ? "ft-" + m + "-20" : "ft-genericfile-32"
    }
    // OneDrive's feed glyphs: Edit, MovetoFolder, Rename, Share, Add, Trash,
    // Refresh, Comment, Reply, Accounts.
    function activityIcon(kind) {
        return ({ edit: "edit-16", move: "folder-arrow-right-16", version: "folder-arrow-right-16", rename: "rename-16", share: "share-16",
                  create: "add-16", delete: "delete-16", restore: "arrow-clockwise-16", reactivate: "arrow-clockwise-16",
                  comment: "comment-16", commentResponse: "arrow-reply-16", mention: "mention-16", copy: "copy-16" })[kind] || "edit-16"
    }
    function size(n) {
        if (typeof n !== "number") return ""
        if (n === 1) return "1 byte"
        const f = v => v >= 100 || v === Math.floor(v) ? v.toFixed(0) : v.toFixed(v >= 10 ? 1 : 2)
        if (n < 1024) return n + " bytes"
        if (n < 1024e3) return f(n / 1024) + " KB"
        if (n < 1048576e3) return f(n / 1048576) + " MB"
        return f(n / 1073741824) + " GB"
    }
    // Test hooks
    function stateForTest() {
        return { loading: loading, error: error, notify: notify, people: info && info.people ? info.people.length : -1, links: info ? !!info.links : false,
                 thumbnail: info ? !!info.thumbnail : false, groups: feed.map(a => a.group + ": " + (a.comment_id ? a.author + " commented: " : "") + a.text.replace(/<[^>]+>/g, "") + " · " + a.time),
                 more: info && !folderMode ? [info.details.type_text, info.details.modified, info.details.created, info.details.path.join(" › ")] : [], folder: folderMode }
    }
    function bellForTest() { notify = !notify; backend.driveAction(tag + "notify", JSON.stringify(item), JSON.stringify({ on: notify })) }
    function commentForTest(text) { commentBox.text = text; send() }
    function editCommentForTest(text, to) { const c = feed.find(a => a.comment_id && a.source === text); if (c) sendEdit(c.comment_id, to); return !!c }
    function replyForTest(text, reply) { const c = feed.find(a => a.comment_id && a.source === text); if (c) sendReply(c.comment_id, reply); return !!c }
    function startEditForTest(text) { const c = feed.find(a => a.comment_id && a.source === text); if (c) editingId = c.comment_id; return !!c }
    function commentsForTest() { return feed.filter(a => a.comment_id).map(a => a.author + ": " + a.source + " · " + a.time + (a.edited ? " • Edited" : "") + (a.replies || []).map(r => " | " + r.author + " replied: " + r.text + " · " + r.time).join("")) }
    function deleteCommentForTest(text) { const c = feed.find(a => a.comment_id && (a.source === text || a.text === text)); if (c) backend.driveAction(tag + "delete_comment", JSON.stringify(item), JSON.stringify({ id: c.comment_id })); return !!c }
    function scrollForTest(y) { flick.contentY = Math.min(y, Math.max(0, flick.contentHeight - flick.height)) }
}
