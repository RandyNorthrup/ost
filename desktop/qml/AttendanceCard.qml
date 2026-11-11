import QtQuick

// Teams' Attendance card under a meeting's end (attendance-report-message-
// wrapper), measured on winpc 2026-11-11 (CSS px): 321.3 x 49.3, #E6E6E6
// (#FAFAFA on hover), radius 4, Fluent's shadow2; the report glyph (32) at
// 12.7, 8.7; "Attendance" 14/600 #242424 at 56.7, vertically centred.
// Teams shows it to the meeting's organizer and co-organizers; clicking
// opens its Attendance view.
Rectangle {
    id: card
    signal clicked()
    width: 321.3; height: 49.3; radius: 4
    color: h.hovered ? theme.pick("#FAFAFA", "#3D3D3D") : theme.pick("#E6E6E6", "#2E2E2E")
    FluentSurface { anchors.fill: parent; z: -1; depth: 2; radius: 4; color: "transparent" }
    Image {
        x: 12.7; y: 8.7; width: 32; height: 32
        source: "../assets/icons/attendance-report-32.svg"
        sourceSize: Qt.size(64, 64)
    }
    Text {
        x: 56.7; anchors.verticalCenter: parent.verticalCenter
        text: "Attendance"
        font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
        color: theme.text
    }
    HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: card.clicked() }
    Accessible.role: Accessible.Button
    Accessible.name: "Attendance Download the attendance report"
}
