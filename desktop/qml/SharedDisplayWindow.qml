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
    title: "Meeting join | " + (call ? call.peer : "") + " | OST"
    width: 1280; height: 680
    color: "#F5F5F5"
    onClosing: if (call) call.roomMode = false
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
        Rectangle { width: 0.67; height: parent.height; color: "#E0E0E0" }
        PeoplePane {
            anchors.fill: parent
            display: true
            people: room.call ? room.call.people : []
            chatMembers: room.call ? room.call.chatMembers : []
            meeting: true
        }
    }
}
