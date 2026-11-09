import QtQuick
import QtQuick.Controls.Basic

// Manage notifications ▸ Customize (Teams' channel notification dialog,
// measured on winpc 2026-11-09): 656 wide, padding 32, radius 8.
// - The team's picture (32, radius 4) beside the channel's name (14/20
//   bold) and "Manage notifications" (12/16 #424242).
// - "Select what content notifies you" (14/20 bold), what it counts (12/16
//   #424242), then three cards (radius 8, a 0.67 px #D1D1D1 line, 8
//   apart): the radio (16) at 24.6, the icon (20) at 56, the name (14/20)
//   and what it means (12/16) at 84.6; unchosen ones in #616161. Under
//   "@mentions and replies" (when chosen): Follow all new threads, Tag
//   mentions, Channel and team mentions (32 rows, the box at 58.6).
// - "Set a desktop notification preference" (14/20 bold) and its note with
//   the link to every channel's settings; "Set a preference for this
//   channel" with Match settings used for all channels / Get notified for
//   selected content / Don't get desktop notifications.
// - Cancel and Save (96 x 31.3, 8 apart); Save once something changed.
// Saving writes channelNotificationSettings, alerts and followAllRc as
// Teams does.
Popup {
    id: dlg
    property string teamId: ""
    property string teamName: ""
    property string newestPost: ""
    property var channel: ({})
    // What the channel has, and what's chosen.
    property var loaded: null
    property string mode: "mentions"
    property bool followAll: false
    property bool tag: true
    property bool channelTeam: true
    property string dsk: ""
    property bool saving: false
    readonly property bool changed: !!loaded && (mode !== loaded.mode || followAll !== loaded.follow_all
        || tag !== loaded.tag || channelTeam !== loaded.channel_team || dsk !== (loaded.dsk || ""))
    signal openNotificationSettings()

    function start(c) {
        channel = c; loaded = null; saving = false
        backend.channelAction("notify-load", teamId, c.id, "")
        open()
    }
    Connections {
        target: backend
        function onChannelActionResultChanged() {
            const r = JSON.parse(backend.channelActionResult || "{}")
            if (r.channel !== dlg.channel.id) return
            if (r.op === "notify-load" && r.ok && r.data) {
                dlg.loaded = r.data
                dlg.mode = r.data.mode; dlg.followAll = r.data.follow_all
                dlg.tag = r.data.tag; dlg.channelTeam = r.data.channel_team; dlg.dsk = r.data.dsk || ""
            } else if (r.op === "customize") {
                dlg.saving = false
                if (r.ok) dlg.close()
            }
        }
    }
    function save() {
        saving = true
        backend.channelAction("customize", teamId, channel.id, JSON.stringify({
            mode: mode, tag: tag, channel_team: channelTeam, dsk: dsk || null,
            follow_all: followAll, newest: newestPost }))
    }

    anchors.centerIn: Overlay.overlay
    modal: true; width: 656
    padding: 32
    height: Math.min(implicitHeight, (Overlay.overlay ? Overlay.overlay.height : 680) - 24)
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }

    component Card: Rectangle {
        id: card
        property string key
        property string icon
        property string label
        property string hint
        default property alias extra: extraCol.data
        readonly property bool chosen: dlg.mode === key
        width: parent.width
        height: 12 + 40 + (chosen && extraCol.children.length ? extraCol.height + 8 : 0) + 9.3
        radius: 8
        color: cardHover.hovered && !chosen ? theme.pick("#E8EBFA", "#2F2F4A") : "transparent"
        border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
        readonly property color ink: chosen ? theme.text : theme.textSecondary
        Rectangle {
            x: 24.6; y: 22.6 - 7.6; width: 16; height: 16; radius: 8
            color: "transparent"
            border.color: card.chosen ? theme.brand : theme.textSecondary; border.width: 0.67
            Rectangle { visible: card.chosen; anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: theme.brand }
        }
        FluentIcon { x: 56; y: 12.6; size: 20; name: card.icon; color: card.ink }
        Column {
            x: 84.6; y: 12.6; width: parent.width - 84.6 - 16
            Text { text: card.label; font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: card.ink }
            Text { width: parent.width; wrapMode: Text.Wrap; text: card.hint; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: card.ink }
        }
        HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: dlg.mode = card.key }
        Column {
            id: extraCol
            visible: card.chosen
            x: 50.6; y: 60.7
        }
        Accessible.role: Accessible.RadioButton
        Accessible.checked: chosen
        Accessible.name: label
    }
    component Check: Item {
        id: chk
        property string label
        property bool checked
        signal toggled()
        width: 400; height: 32
        Rectangle {
            x: 8; y: 8; width: 16; height: 16; radius: 2
            color: chk.checked ? theme.brand : "transparent"
            border.color: chk.checked ? theme.brand : theme.textSecondary; border.width: 0.67
            FluentIcon { visible: chk.checked; anchors.centerIn: parent; size: 12; name: "checkmark-12"; color: "white" }
        }
        Text {
            x: 36; anchors.verticalCenter: parent.verticalCenter
            text: chk.label
            font.family: theme.font; font.pixelSize: 14
            color: chk.checked ? theme.text : theme.textSecondary
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: chk.toggled() }
        Accessible.role: Accessible.CheckBox
        Accessible.checked: checked
        Accessible.name: label
    }

    contentItem: Item {
        implicitHeight: body.implicitHeight + 24 + 31.3
        Flickable {
            id: flick
            width: parent.width; height: parent.height - 24 - 31.3
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
                id: body
                width: flick.width
                spacing: 0
                Item {
                    width: parent.width; height: 32 + 32
                    Avatar {
                        x: 0.7; y: 3.7; size: 32; square: true
                        name: dlg.teamName
                        initialsText: dlg.teamName.split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0]).join("").toUpperCase()
                        photoId: dlg.teamId ? "team:" + dlg.teamId : ""
                    }
                    Text { x: 44.7; y: 0.7; text: dlg.channel.name || ""; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                    Text { x: 44.7; y: 22.7; text: "Manage notifications"; font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong }
                }
                Text { text: "Select what content notifies you"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text {
                    width: parent.width; topPadding: 4; wrapMode: Text.Wrap
                    text: "Your notification count will include this content, even when device notifications are off. Personal @mentions and replies to followed threads are always included."
                    font.family: theme.font; font.pixelSize: 12; lineHeight: 16; lineHeightMode: Text.FixedHeight; color: theme.textStrong
                }
                Item { width: 1; height: 20 }
                Column {
                    width: parent.width; spacing: 8
                    Card { key: "all"; icon: "alert-on-20"; label: "All new messages"; hint: "New messages, all @mentions, and replies to followed threads" }
                    Card {
                        key: "mentions"; icon: "alert-20"; label: "@mentions and replies"; hint: "All @mentions and replies to followed threads"
                        Check { label: "Follow all new threads"; checked: dlg.followAll; onToggled: dlg.followAll = !dlg.followAll }
                        Check { label: "Tag mentions"; checked: dlg.tag; onToggled: dlg.tag = !dlg.tag }
                        Check { label: "Channel and team mentions"; checked: dlg.channelTeam; onToggled: dlg.channelTeam = !dlg.channelTeam }
                    }
                    Card { key: "mute"; icon: "alert-off-20"; label: "Mute"; hint: "You'll still be notified for personal mentions and replies to followed threads" }
                }
                Item { width: 1; height: 20 }
                Text { text: "Set a desktop notification preference"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.Bold; lineHeight: 20; lineHeightMode: Text.FixedHeight; color: theme.text }
                Text {
                    width: parent.width; topPadding: 4; wrapMode: Text.Wrap
                    textFormat: Text.StyledText
                    text: "Desktop notifications are on for all channels. Go to <a href=\"settings\">notifications settings for all channels</a>"
                    font.family: theme.font; font.pixelSize: 12; color: theme.textStrong
                    linkColor: theme.brandForeground1
                    onLinkActivated: { dlg.close(); dlg.openNotificationSettings() }
                    HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
                }
                Item { width: 1; height: 8 }
                Item {
                    width: parent.width; height: 31.3
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Set a preference for this channel"; font.family: theme.font; font.pixelSize: 14; color: theme.text }
                    Dropdown {
                        x: parent.width - width; width: 294; height: 31.3
                        options: [["", "Match settings used for all channels"], ["On", "Get notified for selected content"], ["Off", "Don't get desktop notifications"]]
                        label: options.find(o => o[0] === dlg.dsk)[1]
                        onPicked: code => dlg.dsk = code
                        accessibleName: "Set a preference for this channel"
                    }
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            spacing: 8
            Rectangle {
                width: 96; height: 31.3; radius: 4
                color: cancelHover.hovered ? theme.rowHover : theme.surface
                border.color: theme.pick("#D1D1D1", "#666666"); border.width: 0.67
                Text { anchors.centerIn: parent; text: "Cancel"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.text }
                HoverHandler { id: cancelHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: dlg.close() }
                Accessible.role: Accessible.Button; Accessible.name: "Cancel"
            }
            Rectangle {
                readonly property bool on: dlg.changed && !dlg.saving
                width: 96; height: 31.3; radius: 4
                color: !on ? theme.pick("#F0F0F0", "#141414") : saveHover.hovered ? theme.brandHover : theme.brandFill
                Text { anchors.centerIn: parent; text: "Save"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: parent.on ? "white" : theme.disabled }
                HoverHandler { id: saveHover; cursorShape: parent.on ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { enabled: parent.on; onTapped: dlg.save() }
                Accessible.role: Accessible.Button; Accessible.name: "Save"
            }
        }
    }
}
