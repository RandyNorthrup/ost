import QtQuick
import QtQuick.Window

// Teams' shared display (View › More options › Optimize for room): a
// second window to put on a room's screen, "Meeting join | <meeting>",
// with the gallery (cameras shown here, not in the call window) and the
// participants list, nothing else (measured on winpc: the stage inset
// 2.67, the 360 px pane on #F5F5F5 with a 0.67 #E0E0E0 edge).
Window {
    id: room
    /// The call window.
    property var call
    title: qsTr("Meeting join | %1").arg(call ? call.peer : "") + " | OST"
    width: 1280; height: 680
    color: theme.hc("#F5F5F5", "#000000")
    onClosing: if (call) call.roomMode = false
    // Teams opens it maximized on the room's display (a screen other than
    // this device's), else over this screen's work area, without
    // taking focus from the call window.
    flags: Qt.Window | Qt.WindowDoesNotAcceptFocus
    Component.onCompleted: {
        // This device's screen is the call window's; any other is the room's.
        const screens = Qt.application.screens
        const mine = call && call.screen ? call.screen : screens[0]
        let other = null
        for (let i = 0; i < screens.length; i++) if (screens[i].name !== mine.name) { other = screens[i]; break }
        const s = other || mine
        screen = s
        x = s.virtualX; y = s.virtualY
        width = other ? s.width : s.desktopAvailableWidth
        height = other ? s.height : s.desktopAvailableHeight
        visibility = Window.Maximized
    }
    GalleryGrid {
        x: 2.67; y: 2.67
        width: parent.width - 360 - 5.33; height: parent.height - 5.33
        call: room.call
        forRoom: true
        people: room.call ? (room.call.hideMe ? [] : [room.call.selfEntry]).concat(room.call.othersOrdered).slice(0, room.call.gallerySize) : []
    }
    Rectangle {
        x: parent.width - 360; width: 360; height: parent.height
        color: theme.pane
        Rectangle { width: 0.67; height: parent.height; color: theme.hc("#E0E0E0", "#000000") }
        PeoplePane {
            anchors.fill: parent
            display: true
            people: room.call ? room.call.people : []
            chatMembers: room.call ? room.call.chatMembers : []
            meeting: true
        }
    }
}
