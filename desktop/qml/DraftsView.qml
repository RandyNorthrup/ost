import QtQuick
import QtQuick.Controls.Basic

// Quick views > Drafts, as Teams desktop lays it out (measured at 1x): a
// 380 px white list of chats with unsent text, and a hint beside it.
Rectangle {
    id: root
    /// [{id, name, peerMri, text, time}], newest first.
    property var drafts: []
    signal openDraft(string id, string name)
    property string chip: ""
    readonly property var shown: drafts.filter(d => !chip
        || (chip === "channels" ? d.id.endsWith("@thread.tacv2") : !d.id.endsWith("@thread.tacv2")))
    color: theme.surface
    // Up / Down / Home / End through the drafts (ListKeys). Opening a draft
    // leaves this view for its chat, so Enter or Space opens it whatever
    // the setting says.
    ListKeys {
        id: keys
        owner: root
        view: list
        items: root.shown
        enterToOpen: true
        onOpen: d => root.openDraft(d.id, d.name)
    }
    Keys.onPressed: e => keys.handle(e, "")
    function keysForTest() { return keys }
    onVisibleChanged: if (visible) forceActiveFocus()

    Rectangle {
        id: pane
        width: 380; height: parent.height
        color: theme.surface
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: theme.dividerSoft }

        Text {
            x: 32; y: 19
            text: qsTr("Drafts")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
            color: theme.text
        }
        Row {
            x: 32; y: 69
            spacing: 4
            Repeater {
                model: [{ key: "channels", label: qsTr("Channels") }, { key: "chats", label: qsTr("Chats") }]
                delegate: Rectangle {
                    id: dchip
                    required property var modelData
                    readonly property bool on: root.chip === modelData.key
                    height: 24; radius: 12
                    width: chipText.implicitWidth + 16
                    color: on ? theme.hc(theme.brandTint, theme.hcHighlight) : (dch.hovered ? theme.rowHover : "transparent")
                    border.color: on ? theme.brand : theme.stroke
                    HoverHandler { id: dch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.chip = dchip.on ? "" : dchip.modelData.key }
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: modelData.label
                        font.family: theme.font; font.pixelSize: theme.small
                        color: theme.onFill(dchip, dchip.on ? theme.brand : theme.textStrong)
                    }
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: modelData.label
                    Accessible.checked: on
                }
            }
        }

        ListView {
            id: list
            y: 106
            width: parent.width - 1; height: parent.height - y
            clip: true
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Item {
                id: item
                required property var modelData
                width: list.width; height: 60
                Rectangle {
                    id: hcFill1
                    x: 16; width: parent.width - 32; height: parent.height; radius: theme.radius
                    color: itemHover.hovered ? theme.hc(theme.pane, theme.hcHighlight) : "transparent"
                }
                Rectangle {
                    visible: keys.ringOn(item.modelData)
                    z: 2
                    x: 16; width: parent.width - 32; height: parent.height; radius: theme.radius
                    color: "transparent"; border.width: 2; border.color: theme.text
                }
                Avatar {
                    x: 32; y: 16
                    size: 32; name: item.modelData.name || "?"
                    photoId: item.modelData.peerMri || ""
                }
                Text {
                    x: 80; y: 13; width: parent.width - 80 - 56
                    text: item.modelData.name || qsTr("Chat")
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: theme.base; font.weight: Font.DemiBold
                    color: theme.onFill(hcFill1, theme.text)
                }
                Text {
                    x: 80; y: 37; width: parent.width - 80 - 56
                    text: qsTr("You: %1").arg(item.modelData.text.replace(/\s+/g, " "))
                    elide: Text.ElideRight
                    font.family: theme.font; font.pixelSize: theme.base; font.italic: true
                    color: theme.onFill(hcFill1, theme.text)
                }
                HoverHandler { id: itemHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { keys.clicked(item.modelData); root.openDraft(item.modelData.id, item.modelData.name) } }
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Draft to %1").arg(item.modelData.name)
            }
        }
        // Nothing pending (Teams web 2026-11-27, Drafts is always listed):
        // Teams' 192 px check picture centred in the pane from 101 down to
        // 100 above its bottom, and "You have no draft messages." (16/24
        // bold) 20 under it.
        Item {
            id: emptyArea
            visible: root.shown.length === 0
            y: 101; width: parent.width - 1; height: parent.height - 101 - 100
            Image {
                id: emptyPicture
                x: (parent.width - width) / 2; y: (parent.height - height) / 2
                width: 192; height: 192
                source: "../assets/illustrations/drafts-empty.png"
                sourceSize: Qt.size(192, 192)
            }
            Text {
                x: 21; y: emptyPicture.y + emptyPicture.height + 20; width: parent.width - 42
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("You have no draft messages.")
                font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold
                lineHeight: 24; lineHeightMode: Text.FixedHeight
                color: theme.text
            }
        }
    }

    Column {
        visible: root.shown.length > 0
        anchors.centerIn: hint
        spacing: 16
        FluentIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "drafts-20"; size: 64; color: theme.brand }
        Text {
            text: qsTr("Select a draft to edit and send.")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            color: theme.text
        }
    }
    Item { id: hint; anchors { left: pane.right; right: parent.right; top: parent.top; bottom: parent.bottom } }
}
