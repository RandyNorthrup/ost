import QtQuick
import QtQuick.Controls.Basic

// Teams' "More meeting chat options" (MeetingChatOptionsTrigger, read in
// Teams' meeting-relevant-people code and measured on winpc 2026-11-27): a
// 240 wide menu under the ··· button, its end at the button's: "Options"
// (12/600 #616161), "Allow chat tabs" with its glyph and a switch at the
// end; with chat tabs open, "Close all tabs", a divider, "Chat tabs" and
// each tab (its picture and name) with Open in new window and Close this
// tab.
Popup {
    id: root
    property bool allowTabs: true
    /// [{threadId, title, members: [{id, name}]}]
    property var tabs: []
    signal allowTabsToggled(bool on)
    signal closeAllTabs()
    signal closeTab(string threadId)
    signal popoutTab(string threadId)
    width: 240
    padding: 4
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    background: FluentSurface { depth: 16; radius: 4; color: theme.menu }
    /// Open under the header button, its end at the button's (parented to
    /// the header, which outlives its buttons).
    function openFor(button) {
        parent = button.parent
        x = button.x + button.width - width; y = button.y + button.height + 2
        open()
    }

    contentItem: Column {
        spacing: 2
        Text {
            x: 8; height: 32; verticalAlignment: Text.AlignVCenter
            text: qsTr("Options")
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            color: theme.textSecondary
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Row_ {
            icon: "square-multiple-20"
            label: qsTr("Allow chat tabs")
            switchOn: root.allowTabs
            onActivated: root.allowTabsToggled(!root.allowTabs)
        }
        Row_ {
            visible: root.tabs.length > 0
            icon: "dismiss-square-multiple-20"
            label: qsTr("Close all tabs")
            onActivated: { root.close(); root.closeAllTabs() }
        }
        Item {
            visible: root.tabs.length > 0
            width: root.availableWidth; height: 9
            Rectangle { x: -4; y: 4; width: root.width; height: Math.max(0.67, 1 / Screen.devicePixelRatio); color: theme.divider }
        }
        Text {
            visible: root.tabs.length > 0
            x: 8; height: 32; verticalAlignment: Text.AlignVCenter
            text: qsTr("Chat tabs")
            font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            color: theme.textSecondary
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
        Repeater {
            model: root.tabs
            Row_ {
                id: tabRow
                required property var modelData
                label: modelData.title
                person: modelData.members.length === 1 ? modelData.members[0].id : ""
                chevron: true
                onActivated: { tabMenu.threadId = modelData.threadId; tabMenu.parent = tabRow; tabMenu.x = tabRow.width; tabMenu.y = 0; tabMenu.open() }
            }
        }
    }
    MenuPopup {
        id: tabMenu
        property string threadId
        items: [{ label: qsTr("Open in new window"), icon: "window-new-20" }, { label: qsTr("Close this tab"), icon: "dismiss-20" }]
        onPicked: i => { const id = threadId; root.close(); if (i === 0) root.popoutTab(id); else root.closeTab(id) }
    }

    // A menu row: 32 tall (36 with a switch), its 20 px glyph 6 in (or a
    // 20 px picture), the label at 30, a 40 x 20 switch 8 from the end.
    component Row_: Rectangle {
        id: r
        property string icon
        property string person: ""
        property string label
        property bool chevron: false
        property var switchOn: undefined
        readonly property bool isSwitch: switchOn !== undefined
        signal activated()
        width: root.availableWidth; height: isSwitch ? 36 : 32; radius: 4
        color: rh.hovered ? theme.menuHover : "transparent"
        FluentIcon {
            visible: !!r.icon
            x: 6; anchors.verticalCenter: parent.verticalCenter; size: 20
            name: r.icon; color: rh.hovered ? theme.brand : theme.textStrong
        }
        Avatar {
            visible: !r.icon
            x: 6; anchors.verticalCenter: parent.verticalCenter; size: 20
            name: r.label; photoId: r.person
        }
        Text {
            x: 30; width: parent.width - 30 - (r.isSwitch ? 56 : r.chevron ? 28 : 8)
            anchors.verticalCenter: parent.verticalCenter
            text: r.label; elide: Text.ElideRight
            font.family: theme.font; font.pixelSize: 14
            color: rh.hovered ? theme.text : theme.textStrong
        }
        Rectangle {
            visible: r.isSwitch
            anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 20; radius: 10
            color: r.switchOn ? (rh.hovered ? theme.brandHover : theme.checkedFill) : "transparent"
            border.width: r.switchOn ? 0 : 0.67
            border.color: rh.hovered ? theme.text : theme.textStrong
            Rectangle {
                width: 14; height: 14; radius: 7
                anchors.verticalCenter: parent.verticalCenter
                x: r.switchOn ? parent.width - width - 3 : 3
                color: r.switchOn ? theme.hc("white", "#1AEBFF") : (rh.hovered ? theme.text : theme.textStrong)
            }
        }
        FluentIcon {
            visible: r.chevron
            anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
            name: "chevron-right-16"; size: 16; color: theme.textStrong
        }
        HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: r.activated() }
        Accessible.role: r.isSwitch ? Accessible.CheckBox : Accessible.MenuItem
        Accessible.name: r.label
        Accessible.checkable: r.isSwitch
        Accessible.checked: r.switchOn === true
    }
}
