import QtQuick
import QtQuick.Controls.Basic

// A chat's Notes tab (Teams' FluidThread, chattabs.chatnotes), measured in
// Teams on the web on 2026-11-16 (docs/spec/chat-tabs.md):
// - Teams' header for the Loop page (the Loop host's shared header with
//   Teams' overrides): 48 tall, padding 0 16; "Notes" (14/20 semibold) 28
//   in and 14 down; the 20 px lock (NeutralForeground2), tooltip "Only
//   accessible to members of this chat" below it, 16 from the right; a
//   #E0E0E0 hairline under it;
// - the page: the chat's Loop file (loop_loopThread.loop), shown with
//   Loop's own page container as Teams hosts it (LoopPage,
//   docs/spec/loop-host.md), filling the tab under the header;
// - while the file is being made or the page loads: Teams' state page, the
//   workspace picture (192) over "Give us a moment while we get things
//   ready for you..." (16/22 bold, centred); errors: the warning picture,
//   "Your notes are temporarily not available." with Retry, or "Your notes
//   have been deleted." with Create new.
Rectangle {
    id: root
    property string chat: ""
    /// Where the page is shared (Shared locations), e.g. the chat's name.
    property string location: ""
    color: theme.surface
    readonly property var notes: {
        const s = backend.chatNotesJson ? JSON.parse(backend.chatNotesJson) : null
        return s && s.chat === chat ? s : null
    }
    /// The harness shows each page (--chat-tab-test).
    property string stateForTest: ""
    // The file's state, then the page's: ready once Loop's page is drawn.
    readonly property string fileState: notes ? notes.state : "preparing"
    readonly property string state_: stateForTest || (fileState !== "ready" ? fileState
                                     : !loop.item || loop.item.state_ === "loading" ? "preparing"
                                     : loop.item.state_ === "error" ? "failed" : "ready")
    readonly property bool busy: !notes || !!notes.busy
    function load(create, recreate) { if (chat) backend.chatNotesLoad(chat, create, recreate) }
    // Opening the tab makes the notes when the chat has none (Teams).
    onChatChanged: load(true, false)
    Component.onCompleted: load(true, false)
    // Teams follows a file being made through the thread's updates; OST
    // reads the thread again every few seconds.
    Timer {
        interval: 3000; repeat: true
        running: root.visible && root.fileState === "preparing" && !root.busy
        onTriggered: root.load(false, false)
    }
    readonly property string pageUrl: notes && notes.url ? notes.url : ""

    // Teams' header.
    Item {
        id: header
        width: parent.width; height: 48
        Text {
            x: 28; y: 14; height: 20
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Notes")
            font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        FluentIcon {
            id: lock
            anchors.right: parent.right; anchors.rightMargin: 16; y: 14
            name: "lock-closed-20"; size: 20; color: theme.textStrong
            HoverHandler { id: lockHover }
            ToolTip.visible: lockHover.hovered; ToolTip.delay: 300
            ToolTip.text: qsTr("Only accessible to members of this chat")
            Accessible.role: Accessible.Graphic
            Accessible.name: qsTr("Only accessible to members of this chat")
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.divider }
    }

    Item {
        id: body
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
    }
    // Loop's page, once the chat has its notes file.
    Loader {
        id: loop
        anchors.fill: body
        active: root.fileState === "ready" && root.pageUrl.length > 0 && !root.stateForTest
        sourceComponent: LoopPage { kind: "fluidThread"; componentUrl: root.pageUrl }
    }
    function loopForTest() { return loop.item }

    // Teams' state pages (Ir): the picture, the message and its button.
    Column {
        visible: root.state_ !== "ready"
        anchors.centerIn: body
        width: Math.min(parent.width - 40, 600)
        spacing: 0
        readonly property bool error: root.state_ !== "preparing" && root.state_ !== "ready"
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 192; height: 192; sourceSize: Qt.size(384, 384)
            source: "../assets/illustrations/" + (parent.error ? "warning" : "workspace") + (theme.dark || theme.highContrast ? "-d-" : "-l-") + "standard.svg"
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: root.state_ === "preparing" ? qsTr("Give us a moment while we get things ready for you...")
                : root.state_ === "deleted" ? qsTr("Your notes have been deleted.")
                : qsTr("Your notes are temporarily not available.")
            lineHeight: 22; lineHeightMode: Text.FixedHeight
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; color: theme.text
            Accessible.role: Accessible.Heading; Accessible.name: text
        }
        Item { width: 1; height: 12; visible: action.visible }
        Rectangle {
            id: action
            visible: parent.error
            anchors.horizontalCenter: parent.horizontalCenter
            width: actionText.implicitWidth + 24; height: 32; radius: 4
            color: !enabled ? theme.bgDisabled : actionHover.hovered ? theme.brandHover : theme.brandFill
            enabled: !root.busy
            readonly property string label: root.state_ === "deleted" ? qsTr("Create new") : qsTr("Retry")
            Text {
                id: actionText
                anchors.centerIn: parent
                text: action.label
                font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                color: action.enabled ? theme.textOnBrand : theme.disabled
            }
            HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    // Retry: the page again when the file is there, else the file.
                    if (root.fileState === "ready" && loop.item) loop.item.reload()
                    else root.load(true, root.state_ === "deleted")
                }
            }
            Accessible.role: Accessible.Button; Accessible.name: label
        }
    }
}
