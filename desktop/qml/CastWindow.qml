import QtQuick

// Teams' Cast window (Settings and more ▸ Cast; measured on winpc
// 2026-11-15): a 626 x 713 window, always dark, under Teams' child-window
// title row ("Cast"). A #292929 band (y 32-92) with the brand Cast tile
// (32 px, #4F52B2, radius 4, the white 20 px cast glyph) 20 in and "Cast"
// (16.38/23.4 bold in Teams; 16 here, Qt sizes are whole pixels) at 64; on #1F1F1F, "Select a nearby Teams Room"
// (16/22) centred at 104 and the search line (14/20) at 141: "Searching
// for nearby Teams Rooms..." for 20 s, then "Didn't find any Teams Rooms
// nearby that we can cast to."; Next (96 x 32, disabled until a room is
// picked) 52 from the right, 20.33 from the bottom. Teams finds rooms by
// their proximity beacons; with none in range (no Teams Rooms device here)
// the search ends with nothing found, as Teams' does.
Window {
    id: win
    property bool pinned: false
    property bool searching: true
    title: qsTr("Cast")
    width: 626; height: 713
    minimumWidth: 400; minimumHeight: 400
    color: theme.hc("#1F1F1F", "#000000")
    flags: Qt.Window | (pinned ? Qt.WindowStaysOnTopHint : 0)
    function start() { searching = true; searchTimer.restart(); show(); raise(); requestActivate() }
    Timer { id: searchTimer; interval: 20000; onTriggered: win.searching = false }
    Rectangle { anchors.fill: parent; color: theme.hc("#1F1F1F", "#000000") }

    ChildWindowTitleBar {
        id: titleRow
        title: qsTr("Cast")
        pinned: win.pinned
        onTogglePin: win.pinned = !win.pinned
    }
    Rectangle {
        y: 32; width: parent.width; height: 60
        color: theme.hc("#292929", "#000000")
        Rectangle {
            id: hcFill1
            x: 20; y: 14; width: 32; height: 32; radius: 4
            color: theme.hc("#4F52B2", "#FFFFFF")
            FluentIcon { anchors.centerIn: parent; name: "cast-20"; size: 20; color: theme.onFill(hcFill1, "#FFFFFF") }
        }
        Text {
            x: 64; y: 18.31
            text: qsTr("Cast")
            font.family: theme.font; font.pixelSize: 16; font.weight: Font.Bold; lineHeight: 23.4; lineHeightMode: Text.FixedHeight
            color: "#FFFFFF"
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter; y: 104
        text: qsTr("Select a nearby Teams Room")
        font.family: theme.font; font.pixelSize: 16; lineHeight: 22; lineHeightMode: Text.FixedHeight
        color: "#FFFFFF"
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter; y: 141
        width: Math.min(implicitWidth, parent.width - 40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: win.searching ? qsTr("Searching for nearby Teams Rooms...") : qsTr("Didn't find any Teams Rooms nearby that we can cast to.")
        font.family: theme.font; font.pixelSize: 14; lineHeight: 20; lineHeightMode: Text.FixedHeight
        color: "#FFFFFF"
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }
    Rectangle {
        x: parent.width - 52 - width; y: parent.height - 20.33 - height
        width: 96; height: 32; radius: 4
        color: theme.hc("#1F1F1F", "#000000")
        Text { anchors.centerIn: parent; text: qsTr("Next"); font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.hc("#5C5C5C", "#3FF23F") }
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Next")
    }
}
