import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

// Teams' "Import CSV file to assign participants to breakout rooms"
// (measured on winpc 2026-11-11): a 610 x 579.67 alert dialog, padding
// 24.67, radius 8. The title (20/28 semibold) and Close; "Your CSV should
// include one column for breakout room names and one column for
// participant email addresses." with the "Download CSV template" link
// (#4F52B2) at 64; a 560.67 x 332 drop zone (2 px dashed #E0E0E0, radius
// 2) at 124 holding a 128 x 128 picture at 216.33, 32 (Teams' own image
// fails to load and shows its "Upload icon" alt text; OST draws Fluent's
// upload arrow there), "Drag and drop a CSV file here, or select one to
// import" at 190 and a 200 wide Import at 240; then "Tips:" (12/600
// #616161) at 476 over three bullets (12/16).
Popup {
    id: root
    parent: Overlay.overlay
    modal: true; focus: true
    padding: 0
    width: 610; height: 579.67
    anchors.centerIn: Overlay.overlay
    closePolicy: Popup.CloseOnEscape
    background: FluentSurface { depth: 64; radius: 8; color: theme.surface }
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.4) }
    signal downloadTemplate()
    signal picked(string path)

    Text {
        x: 24.67; y: 24.67; width: 520.67; height: 31.33
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: "Import CSV file to assign participants to breakout rooms"
        font.family: theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        color: theme.text
    }
    Rectangle {
        x: 553.33; y: 24.67; width: 32; height: 31.33; radius: 4
        color: closeHover.hovered ? theme.menuHover : "transparent"
        FluentIcon { anchors.centerIn: parent; name: "dismiss-20"; size: 20; color: theme.textStrong }
        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
        Accessible.role: Accessible.Button
        Accessible.name: "Close"
    }
    Text {
        x: 24.67; y: 64; width: 560.67
        wrapMode: Text.Wrap
        lineHeight: 20; lineHeightMode: Text.FixedHeight
        // Teams' link isn't underlined.
        textFormat: Text.RichText
        text: "Your CSV should include one column for breakout room names and one column for participant email addresses. <a href=\"template\" style=\"text-decoration:none; color:" + theme.brandForeground1 + "\">Download CSV template</a>"
        font.family: theme.font; font.pixelSize: 14
        color: theme.text
        onLinkActivated: root.downloadTemplate()
        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }
    Rectangle {
        id: zone
        x: 24.67; y: 124; width: 560.67; height: 332; radius: 2
        color: drop.containsDrag ? theme.menuHover : "transparent"
        // Fluent's dashed edge.
        Canvas {
            anchors.fill: parent
            onPaint: {
                const c = getContext("2d")
                c.clearRect(0, 0, width, height)
                c.strokeStyle = theme.divider
                c.lineWidth = 2
                c.setLineDash([3, 3])
                c.strokeRect(1, 1, width - 2, height - 2)
            }
        }
        Item {
            x: 216.33; y: 32; width: 128; height: 128
            FluentIcon { anchors.centerIn: parent; name: "arrow-upload-20"; size: 48; color: theme.textSecondary }
            Accessible.role: Accessible.Graphic
            Accessible.name: "Upload icon"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: 190
            text: drop.containsDrag ? "Drop your file here" : "Drag and drop a CSV file here, or select one to import"
            font.family: theme.font; font.pixelSize: 14
            color: theme.text
        }
        Rectangle {
            x: 180.33; y: 240; width: 200; height: 31.33; radius: 4
            color: importHover.hovered ? theme.brandHover : theme.brandFill
            Text { anchors.centerIn: parent; text: "Import"; font.family: theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: theme.textOnBrand }
            HoverHandler { id: importHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: fileDialog.open() }
            Accessible.role: Accessible.Button
            Accessible.name: "Import"
        }
        DropArea {
            id: drop
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: d => {
                const url = (d.urls || [])[0]
                if (url) { root.close(); root.picked(url.toString().replace(/^file:\/\//, "")) }
            }
        }
    }
    Text {
        x: 24.67; y: 476; height: 16
        text: "Tips:"
        font.family: theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
        color: theme.textSecondary
    }
    Column {
        x: 34.67; y: 492
        Repeater {
            model: [
                "Email addresses must match what participants use to join the meeting, no distribution lists.",
                "You can create up to 100 breakout rooms with a maximum of 1000 participants.",
                "Participants not listed in the CSV will remain in the main meeting."
            ]
            Text {
                required property string modelData
                width: 550.67; height: 16
                text: "• " + modelData
                font.family: theme.font; font.pixelSize: 12
                color: theme.textSecondary
            }
        }
    }
    FileDialog {
        id: fileDialog
        title: "Import"
        nameFilters: ["CSV files (*.csv)"]
        onAccepted: { root.close(); root.picked(selectedFile.toString().replace(/^file:\/\//, "")) }
    }
}
