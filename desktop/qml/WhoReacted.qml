import QtQuick
import QtQuick.Controls.Basic

// Teams' who-reacted list (diverse-reaction-user-list-popover, measured on
// winpc): a Fluent MenuPopover centred under the pill, 4.3 below it, 198
// wide for short names (min 138, rows at most 290), radius 4, shadow 8,
// padding 4 / 0 / 8.
// - The reaction's name as its header: 12 px light, NeutralForeground3,
//   padding 8 / 16 (32 tall).
// - The list (padding 4, at most 236 tall, scrolling): 32 px rows 2 apart,
//   radius 4, padding 6 / 6 / 6 / 12; a 20 px avatar, the name (14 px,
//   NeutralForeground2) at 38; the emoji at the end when the pill mixes skin
//   tones. Newest first.
// - A row opens a 1:1 chat ("Chat with {name}"); Delete or Backspace on your
//   own row removes your reaction.
// Hovering opens it after 300 ms; right-clicking opens it with focus.
Popup {
    id: root
    property string messageId
    property var reaction: null
    signal removeMine(string messageId, string key)
    readonly property var users: reaction ? reaction.users : []
    readonly property bool diverse: reaction ? reaction.variants.length > 1 : false
    // Rows size to the longest name, within Fluent's limits.
    property real nameWidth: 0
    width: Math.min(290, Math.max(189.7, 38 + nameWidth + 4 + (diverse ? 26 : 0) + 15.7)) + 8 + 1.3
    height: 4.7 + 32 + listH + 8 + 0.7
    readonly property real listH: Math.min(236, 8 + users.length * 32 + Math.max(0, users.length - 1) * 2)
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: FluentSurface { depth: 8; radius: 4; color: theme.surface }
    readonly property bool hovered: surfaceHover.hovered
    onUsersChanged: {
        let w = 0
        for (const u of users) { metrics.text = u.name; w = Math.max(w, metrics.advanceWidth) }
        nameWidth = w
    }
    onOpened: if (focus) list.forceActiveFocus()
    TextMetrics { id: metrics; font.family: theme.font; font.pixelSize: theme.base }
    HoverHandler { id: surfaceHover }

    Text {
        x: 16.7; y: 12.7; height: 16; verticalAlignment: Text.AlignVCenter
        text: root.reaction ? backend.emoticonName(root.reaction.key) : ""
        font.family: theme.font; font.pixelSize: theme.small; font.weight: Font.Light
        color: theme.textSecondary
    }
    ListView {
        id: list
        x: 4.7; y: 40.7
        width: root.width - 9.4; height: root.listH - 8
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: root.users
        keyNavigationEnabled: true
        currentIndex: 0
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool own: modelData.me
            width: list.width; height: 32; radius: 4
            color: rowHover.hovered || (list.activeFocus && ListView.isCurrentItem) ? theme.menuHover : theme.surface
            Avatar { x: 12; y: 6; size: 20; name: row.modelData.name; photoId: row.modelData.mri }
            Text {
                x: 38; y: 6; height: 20; verticalAlignment: Text.AlignVCenter
                width: row.width - 38 - 6 - (root.diverse ? 26 : 0)
                elide: Text.ElideRight
                text: row.modelData.name
                font.family: theme.font; font.pixelSize: theme.base
                color: rowHover.hovered ? theme.text : theme.textStrong
            }
            Emoticon {
                visible: root.diverse
                x: row.width - 6 - 20; y: 6; key: row.modelData.key; named: "small"; size: 20
            }
            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.chatWith(row.modelData) }
            Accessible.role: Accessible.MenuItem
            Accessible.name: "Chat with " + modelData.name
            Accessible.description: own ? "Delete your reaction (Delete)" : ""
        }
        Keys.onReturnPressed: root.chatWith(root.users[currentIndex])
        Keys.onEnterPressed: root.chatWith(root.users[currentIndex])
        Keys.onPressed: event => {
            if (event.key !== Qt.Key_Delete && event.key !== Qt.Key_Backspace) return
            const u = root.users[currentIndex]
            if (u && u.me) { root.removeMine(root.messageId, u.key); root.close() }
            event.accepted = true
        }
    }
    function chatWith(u) {
        if (!u) return
        close()
        backend.openChatWith(u.mri.replace(/^8:orgid:/, ""), u.name)
    }
    contentItem: Item {
        Accessible.role: Accessible.PopupMenu
        Accessible.name: root.reaction ? backend.emoticonName(root.reaction.key) : ""
    }
}
